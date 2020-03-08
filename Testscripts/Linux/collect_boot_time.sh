#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

#####################################################################################
#
# collect_boot_time.sh
# Description:
#    This script will collect boot time
#
#####################################################################################
# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    SetTestStateAborted
    exit 2
}

# Source constants file and initialize most common variables
UtilsInit

#######################################################################
# Main script body
#######################################################################
output=$(systemd-analyze)
UpdateSummary "$output"
SetTestStateCompleted
exit 0
