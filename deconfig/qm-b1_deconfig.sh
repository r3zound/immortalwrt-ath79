#!/bin/sh
if [ ! -e ../.config ]; then \
	cp qm-b1_config ../.config
else
	rm ../.config*
	cp qm-b1_config ../.config
fi
