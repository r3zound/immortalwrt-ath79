#!/bin/sh
if [ ! -e ../.config ]; then \
	cp wg2626_config ../.config
else
	rm ../.config*
	cp wg2626_config ../.config
fi
