const PERIPHERAL_DISKS = [ "ata-WDC_WD30EFRX-68AX9N0_WD-WMC1T0876678",
                           "ata-WDC_WD30EFRX-68AX9N0_WD-WMC1T0938110",
                           "ata-WDC_WD30EFRX-68AX9N0_WD-WMC1T0965778",
                           "ata-WDC_WD30EFRX-68AX9N0_WD-WMC1T0979299" ]
const SYSTEM_DISKS     = [ "ata-WDC_WD30EFRX-68EUZN0_WD-WMC4N2180527" ]

const MIN_DUTY         = 2   # min RPM if there's no active device
const MIN_ACTIVE_DUTY  = 10  # min RPM if there's an active device, without significant temp load

# NOTE: disregarding the sensor lower limits, a duty cycle of 2 seems like the minimal value
#       where the BMC doesn't kick in and makes the fan spin at full power
