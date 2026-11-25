#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""WE826-Q: 把官方基线 sysupgrade.bin 重新封装成"内置 frpc 插件"的固件。

为什么是"重封装"而不是"从源码编译":
  * WE826-Q 的 zbt_we826-q 设备定义(设备 .mk + ZBT 风格镜像头 + we826q 板级包)
    不在公开的 ImmortalWrt 上游, 也不在 r3zound/immortalwrt-ath79 这棵 ath79 树里;
  * 基线固件内部没有 DTB(设备树由 bootloader 提供), 内核与分区布局由原厂 u-boot 约定;
  => 改 rootfs 再重封装, 是唯一既保留"原厂标准"又能加插件、且不会刷砖的做法。

流程:
  基线 .bin -> 定位 ZBT 512B 头 -> 取出 squashfs -> unsquashfs -> 注入 ipk/frpc 配置
           -> mksquashfs(xz 256K) -> 改写头(rootfs_size) -> 拼回 kernel 区 -> 输出 .bin

用法:
  python3 build_frpc_firmware.py \
      --base baseline/zbt_we826-q-sysupgrade.bin \
      --out out/immortalwrt-ath79-generic-zbt_we826-q-squashfs-sysupgrade.bin \
      --work /tmp/we826q \
      --frpc-ipk dl/frpc_0.51.2-1_mips_24kc.ipk \
      --luci-ipk dl/luci-app-frpc_git-21.175.36114-ad08c8e_all.ipk \
      --i18n-ipk dl/luci-i18n-frpc-zh-cn_git-23.090.62029-650e6d2_all.ipk \
      --server 8.148.70.135 --port 7000 --token '' \
      --proxy we826q-luci:tcp:20061:192.168.2.1:80 \
      --proxy we826q-ssh:tcp:20062:192.168.2.1:22
"""
import argparse
import gzip
import hashlib
import io
import lzma
import os
import shutil
import struct
import subprocess
import sys
import tarfile

ERASE = 0x10000
MASK1M = 0x000FFFFF
FIRMWARE_END = 0xFD0000          # 内核 dmesg: rootfs 一直到 firmware 区末尾


# ----------------------------------------------------------------- 头/镜像
def be32(b, off):
    return struct.unpack_from('>I', b, off)[0]


def patch_rootfs_size(hdr, new_size):
    hdr = bytearray(hdr)
    struct.pack_into('>I', hdr, 0x8C, new_size)
    return bytes(hdr)


def predict(rootfs_offset, bytes_used, rootfs_size, erasesize=ERASE, round_up=True):
    """内核 drivers/mtd/mtdpart.c 的 split_squashfs 规则 -> (split_offset, overlay_size)"""
    tail = rootfs_offset & MASK1M
    x = bytes_used + tail
    if round_up:
        x = ((x + erasesize - 1) // erasesize) * erasesize
    else:
        x = (x // erasesize) * erasesize
    split_offset = rootfs_offset + x - tail
    overlay = rootfs_size - (split_offset - rootfs_offset)
    return split_offset, overlay


# ----------------------------------------------------------------- ipk 安装
def ipk_data_tar(path):
    """ipk = gzip tar(内含 data.tar.gz) 或 ar 归档。

    关键: 必须把内层 data.tar.gz 完整解压到内存再交给 tarfile。
    直接用 'r:gz' 流式打开时, 顺序读取多个成员会让最后的大成员读到 0 字节
    (gzip 流在多次 seek 之后位置错乱), 实测 14MB 的 frpc 二进制会写成空文件。
    """
    raw = open(path, 'rb').read()
    if raw[:8] == b'!<arch>\n':
        off, members = 8, {}
        while off + 60 <= len(raw):
            hdr = raw[off:off + 60]
            name = hdr[0:16].decode().strip().rstrip('/')
            size = int(hdr[48:58].decode().strip() or '0')
            members[name] = raw[off + 60:off + 60 + size]
            off += 60 + size + (size % 2)
        for key in ('data.tar.gz', 'data.tar.xz', 'data.tar.zst'):
            if key in members:
                return _open_plain_tar(members[key])
        raise RuntimeError('ipk 里没有 data 成员: %s' % path)
    outer = tarfile.open(fileobj=io.BytesIO(raw), mode='r:*')
    for m in outer.getmembers():
        if m.name.endswith('data.tar.gz'):
            return _open_plain_tar(outer.extractfile(m).read())
    raise RuntimeError('ipk 里没有 data.tar.gz: %s' % path)


def _open_plain_tar(compressed):
    """把压缩的 tar 解到内存, 返回可寻址的未压缩 TarFile"""
    if compressed[:2] == b'\x1f\x8b':
        plain = gzip.decompress(compressed)
    elif compressed[:6] == b'\xfd7zXZ\x00':
        plain = lzma.decompress(compressed)
    else:
        plain = compressed
    return tarfile.open(fileobj=io.BytesIO(plain), mode='r:')


def make_symlink(link_path, target_path, strict=False):
    """Windows 非管理员常常建不了符号链接; strict=True 时失败即中止(云端 Linux 用)"""
    if os.path.lexists(link_path):
        os.remove(link_path)
    try:
        os.symlink(target_path, link_path)
        return True
    except OSError as ex:
        if strict:
            raise
        print('    [warn] 符号链接失败 %s -> %s: %s' % (link_path, target_path, ex))
        return False


def install_ipk(tree, ipk_path, label, strict_symlinks=False):
    tf = ipk_data_tar(ipk_path)
    count = 0
    for m in tf.getmembers():
        rel = m.name.lstrip('./')
        if not rel:
            continue
        target = os.path.join(tree, rel.replace('/', os.sep))
        if m.isdir():
            os.makedirs(target, exist_ok=True)
            continue
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if m.issym():
            make_symlink(target, m.linkname, strict_symlinks)
            count += 1
            continue
        if m.islnk():
            continue
        if not m.isfile():
            continue
        data = tf.extractfile(m).read()
        with open(target, 'wb') as fh:
            fh.write(data)
        os.chmod(target, m.mode & 0o7777)
        count += 1
    print('  [ipk] %-22s %d 个文件' % (label, count))
    return count


# ----------------------------------------------------------------- frpc 配置
UCI_TEMPLATE = """\
config init
\toption stdout '1'
\toption stderr '1'
\toption user 'frpc'
\toption group 'frpc'
\toption respawn '1'

config conf 'common'
\toption server_addr '{server}'
\toption server_port '{port}'
\toption log_level 'info'
\toption login_fail_exit '0'
\toption disable_log_color 'true'
{token_line}{extra_common}
{proxies}"""

PROXY_TEMPLATE = """\
config conf '{name}'
\toption type '{type}'
\toption local_ip '{local_ip}'
\toption local_port '{local_port}'
\toption remote_port '{remote_port}'
"""


def build_uci(server, port, token, proxies):
    token_line = "\toption token '%s'" % token if token else ''
    extra = "\toption authentication_method 'token'" if token else ''
    body = ''.join(PROXY_TEMPLATE.format(**p) for p in proxies)
    return UCI_TEMPLATE.format(server=server, port=port, token_line=token_line,
                               extra_common=extra, proxies=body)


def ensure_frpc_account(tree):
    """ipk 的 postinst 在装包时建账号; 我们是直接解包进 squashfs, 需要自己补"""
    def has(path, name):
        p = os.path.join(tree, path.replace('/', os.sep))
        if not os.path.isfile(p):
            return False
        for line in open(p, 'r', errors='replace'):
            if line.split(':')[0] == name:
                return True
        return False

    def append(path, line):
        p = os.path.join(tree, path.replace('/', os.sep))
        with open(p, 'a') as fh:
            fh.write(line)

    if not has('etc/passwd', 'frpc'):
        append('etc/passwd', 'frpc:x:9999:9999:frp client:/var/run:/sbin/nologin\n')
    if not has('etc/group', 'frpc'):
        append('etc/group', 'frpc:x:9999:\n')
    if not has('etc/shadow', 'frpc'):
        append('etc/shadow', 'frpc:!::0:0:9999:9999:::\n')
    # frpc 运行时目录
    for d in ('var/run/frpc', 'etc/frp/frpc.d'):
        os.makedirs(os.path.join(tree, d.replace('/', os.sep)), exist_ok=True)


# ----------------------------------------------------------------- 提权
def is_root():
    return os.name == 'posix' and hasattr(os, 'geteuid') and os.geteuid() == 0


def maybe_elevate(ap):
    """unsquashfs 需要 root 才能在解出的目录里创建 /dev 下的字符设备节点。

    GitHub runner 上当前用户不是 root, /dev/console 会创建失败并让 unsquashfs
    返回 2。这里用 sudo 重新执行自身。Windows 本机演练没有 sudo, 直接跳过。
    """
    if ap.no_sudo or os.name != 'posix' or is_root():
        return
    sudo = shutil.which('sudo')
    if not sudo:
        print('[!] 非 root 且找不到 sudo, /dev 设备节点会缺失')
        return
    argv = [sys.executable, os.path.abspath(__file__)] + sys.argv[1:]
    for extra in (['-E'], []):
        cmd = [sudo] + extra + argv
        print('[i] 需要 root 创建 /dev 设备节点, 通过 sudo 重新执行本脚本')
        rc = subprocess.call(cmd)
        if rc == 0:
            sys.exit(0)
    raise SystemExit('sudo 提权失败, 无法创建 /dev 设备节点')


def restore_owner(path):
    """sudo 提权后把产物 chown 回原调用者, 方便后续步骤读写。"""
    uid = os.environ.get('SUDO_UID')
    gid = os.environ.get('SUDO_GID')
    if not uid or not gid:
        return
    try:
        os.chown(path, int(uid), int(gid))
    except OSError:
        pass


# ----------------------------------------------------------------- 主流程
def run(cmd, allow_rc=(0,)):
    print('  $ ' + ' '.join(cmd))
    p = subprocess.run(cmd, capture_output=True, text=True, errors='replace')
    if p.returncode not in allow_rc:
        sys.stderr.write((p.stdout or '')[-4000:] + (p.stderr or '')[-4000:])
        raise SystemExit('命令失败(%d): %s' % (p.returncode, ' '.join(cmd)))
    return p.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--base', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--work', default='./we826q-work')
    ap.add_argument('--frpc-ipk', required=True)
    ap.add_argument('--luci-ipk', default='')
    ap.add_argument('--i18n-ipk', default='')
    ap.add_argument('--server', default='127.0.0.1')
    ap.add_argument('--port', default='7000')
    ap.add_argument('--token', default='')
    ap.add_argument('--proxy', action='append', default=[],
                    help='name:type:remote_port:local_ip:local_port')
    ap.add_argument('--block-size', type=int, default=262144)
    ap.add_argument('--strict-symlinks', action='store_true',
                    help='符号链接创建失败即报错(云端 Linux 构建应开启)')
    ap.add_argument('--partial-unsquashfs-ok', action='store_true',
                    help='允许 unsquashfs 返回 2(Windows 无权限建符号链接时, 仅用于本机演练)')
    ap.add_argument('--unsquashfs', default='unsquashfs')
    ap.add_argument('--mksquashfs', default='mksquashfs')
    ap.add_argument('--no-sudo', action='store_true',
                    help='禁止自动 sudo 提权(root 才能创建 /dev 设备节点)')
    a = ap.parse_args()

    maybe_elevate(a)

    work = os.path.abspath(a.work)
    tree = os.path.join(work, 'tree')
    os.makedirs(work, exist_ok=True)
    if os.path.isdir(tree):
        shutil.rmtree(tree)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)

    base = open(a.base, 'rb').read()
    hdr = base[:512]
    kernel_size = be32(hdr, 0x84)
    rootfs_offset = be32(hdr, 0x88)
    rootfs_size = be32(hdr, 0x8C)
    print('=== 基线头 ===')
    print('  kernel_size   = 0x%X (%d)' % (kernel_size, kernel_size))
    print('  rootfs_offset = 0x%X' % rootfs_offset)
    print('  rootfs_size   = 0x%X (%d)' % (rootfs_size, rootfs_size))
    print('  文件总长      = %d' % len(base))
    if rootfs_offset + rootfs_size > len(base):
        raise SystemExit('基线长度不足, 头与实际不符')

    print('=== 1. 解出 squashfs ===')
    stock = os.path.join(work, 'stock.squashfs')
    with open(stock, 'wb') as fh:
        fh.write(base[rootfs_offset:rootfs_offset + rootfs_size])
    if open(stock, 'rb').read(4) not in (b'hsqs', b'hsqt'):
        raise SystemExit('rootfs_offset 处不是 squashfs')
    allow_rc = (0, 2) if a.partial_unsquashfs_ok else (0,)
    if not is_root():
        allow_rc = (0, 2)
        print('[!] 非 root 运行: /dev 下的字符设备节点无法创建(/dev/console 将缺失), '
              '运行时由 devtmpfs 补齐')
    run([a.unsquashfs, '-no-progress', '-d', tree, stock], allow_rc=allow_rc)

    print('=== 2. 注入 frpc 插件 ===')
    install_ipk(tree, a.frpc_ipk, 'frpc', a.strict_symlinks)
    if a.luci_ipk:
        install_ipk(tree, a.luci_ipk, 'luci-app-frpc', a.strict_symlinks)
    if a.i18n_ipk:
        install_ipk(tree, a.i18n_ipk, 'luci-i18n-frpc-zh-cn', a.strict_symlinks)

    proxies = []
    for spec in a.proxy:
        parts = spec.split(':')
        if len(parts) != 5:
            raise SystemExit('--proxy 格式应为 name:type:remote_port:local_ip:local_port')
        proxies.append(dict(name=parts[0], type=parts[1], remote_port=parts[2],
                            local_ip=parts[3], local_port=parts[4]))
    uci = build_uci(a.server, a.port, a.token, proxies)
    cfg = os.path.join(tree, 'etc', 'config', 'frpc')
    os.makedirs(os.path.dirname(cfg), exist_ok=True)
    with open(cfg, 'w', newline='\n') as fh:
        fh.write(uci)
    os.chmod(cfg, 0o644)
    print('  [cfg] etc/config/frpc (%d 通道)' % len(proxies))

    ensure_frpc_account(tree)

    # 开机自启: /etc/rc.d/S99frpc -> /etc/init.d/frpc
    initd = os.path.join(tree, 'etc', 'init.d', 'frpc')
    if os.path.isfile(initd):
        os.chmod(initd, 0o755)
        rcd = os.path.join(tree, 'etc', 'rc.d')
        os.makedirs(rcd, exist_ok=True)
        link = os.path.join(rcd, 'S99frpc')
        make_symlink(link, '/etc/init.d/frpc', a.strict_symlinks)
        print('  [init] /etc/rc.d/S99frpc 已创建')
    else:
        raise SystemExit('frpc 包里没有 /etc/init.d/frpc')

    print('=== 3. 重建 squashfs (xz, %d 字节块) ===' % a.block_size)
    # 注入结果自检: frpc 二进制不能是空文件/缺失
    frpc_bin = os.path.join(tree, 'usr', 'bin', 'frpc')
    if not os.path.isfile(frpc_bin):
        raise SystemExit('注入后找不到 usr/bin/frpc')
    frpc_size = os.path.getsize(frpc_bin)
    if frpc_size < 1024 * 1024:
        raise SystemExit('usr/bin/frpc 只有 %d 字节, 明显不完整' % frpc_size)
    with open(frpc_bin, 'rb') as fh:
        if fh.read(4) != b'\x7fELF':
            raise SystemExit('usr/bin/frpc 不是 ELF 可执行文件')
    print('  [check] usr/bin/frpc %d 字节, ELF 头正常' % frpc_size)
    for need in ('etc/config/frpc', 'etc/init.d/frpc'):
        p = os.path.join(tree, need.replace('/', os.sep))
        if not os.path.isfile(p) or os.path.getsize(p) == 0:
            raise SystemExit('注入后缺少 %s' % need)
    print('  [check] etc/config/frpc 与 etc/init.d/frpc 就位')

    new_sq = os.path.join(work, 'new.squashfs')
    if os.path.exists(new_sq):
        os.remove(new_sq)
    run([a.mksquashfs, tree, new_sq, '-comp', 'xz', '-b', str(a.block_size),
         '-Xdict-size', str(a.block_size), '-all-root', '-noappend', '-quiet'])
    sq = open(new_sq, 'rb').read()
    sb_bytes_used = struct.unpack_from('<Q', sq, 0x28)[0]
    sb_comp = struct.unpack_from('<H', sq, 0x14)[0]
    sb_block = struct.unpack_from('<I', sq, 0x0C)[0]
    print('  新 squashfs: %d 字节 (compression=%d block=%d)' % (len(sq), sb_comp, sb_block))

    print('=== 4. 重封装镜像 ===')
    kernel = base[512:rootfs_offset]
    out = patch_rootfs_size(hdr, sb_bytes_used) + kernel + sq
    pad = len(base) - len(out)
    if pad < 0:
        print('  新镜像比基线长 %d 字节 (正常)' % (-pad))
    else:
        out += b'\xff' * pad
    with open(a.out, 'wb') as fh:
        fh.write(out)
    digest = hashlib.sha256(out).hexdigest()
    print('  输出: %s' % os.path.abspath(a.out))
    print('  大小: %d 字节' % len(out))
    print('  sha256: %s' % digest)

    print('=== 5. 分区预算校验 ===')
    part = FIRMWARE_END - rootfs_offset
    for ro in (True, False):
        split, overlay = predict(rootfs_offset, sb_bytes_used, part, round_up=ro)
        print('  split=0x%X overlay=%d (%.2f MB) [%s取整]' % (
            split, overlay, overlay / 1048576.0, '向上' if ro else '向下'))
        if overlay <= 0:
            raise SystemExit('squashfs 超出 firmware 分区容量, 刷不进去')
    base_split, base_overlay = predict(rootfs_offset, rootfs_size, part, round_up=True)
    print('  基线对照: split=0x%X overlay=%d' % (base_split, base_overlay))
    print('  overlay 变化: %+d 字节' % (
        predict(rootfs_offset, sb_bytes_used, part, round_up=True)[1] - base_overlay))

    with open(os.path.abspath(a.out) + '.sha256', 'w') as fh:
        fh.write('%s  %s\n' % (digest, os.path.basename(a.out)))
    # sudo 提权时把产物交还给原调用者
    out_abs = os.path.abspath(a.out)
    restore_owner(out_abs)
    restore_owner(out_abs + '.sha256')
    restore_owner(os.path.dirname(out_abs))
    return 0


if __name__ == '__main__':
    sys.exit(main())
