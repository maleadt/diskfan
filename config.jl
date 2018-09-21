const PERIPHERAL_DISKS = [ "ata-WDC_WD30EFRX-68AX9N0_WD-WMC1T0876678",
                           "ata-WDC_WD30EFRX-68AX9N0_WD-WMC1T0938110",
                           "ata-WDC_WD30EFRX-68AX9N0_WD-WMC1T0965778",
                           "ata-WDC_WD30EFRX-68AX9N0_WD-WMC1T0979299" ]
const SYSTEM_DISKS     = [ "ata-WDC_WD30EFRX-68EUZN0_WD-WMC4N2180527" ]

# minimum duty cycle for fans (eg. to prevent them from stopping, and/or maintain airflow)
const MIN_DUTY         = 5
# NOTE: disregarding the sensor lower limits, a duty cycle of 2 seems like the minimal value
#       where the SuperMicro BMC doesn't kick in and makes the fan spin at full power
