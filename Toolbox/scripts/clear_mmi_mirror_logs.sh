#!/bin/sh
# Clear only disposable MMI Mirror logs and installer/launcher self-test leftovers.
# Active controller/HMI/BaseVideo lifecycle files are intentionally retained;
# use Stop to withdraw BaseVideo ownership instead of this diagnostic cleanup action.

RESULT=0
for f in \
    /tmp/mmi-mirror-display.log \
    /tmp/mmi-mirror-display.log.1 \
    /tmp/mmi-mirror-controller.log \
    /tmp/mmi-mirror-controller.log.1 \
    /tmp/mmi-mirror-install-selftest.log \
    /tmp/mmi-mirror-launcher-selftest-bin.sh \
    /tmp/mmi-mirror-launcher-selftest.log \
    /tmp/mmi-mirror-launcher-selftest.log.1 \
    /tmp/mmi-mirror-launcher-selftest.stdout
do
    if [ -e "$f" ]; then
        rm -f "$f" 2>/dev/null || RESULT=1
    fi
done

if [ "${RESULT}" -eq 0 ]; then
    echo "Temporary MMI Mirror logs cleared; runtime state preserved."
else
    echo "WARNING: some temporary MMI Mirror logs could not be removed."
fi
exit "${RESULT}"
