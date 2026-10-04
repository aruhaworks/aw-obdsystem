return {
    qb = {
        obd_scanner = { name = 'obd_scanner', label = 'OBD-II Scanner', weight = 500, type = 'item', image = 'obd_scanner.png', unique = false, useable = true, shouldClose = true, description = 'ARUHAWORKS diagnostic terminal' },
        obd_ghost = { name = 'obd_ghost', label = 'Modified OBD Dongle', weight = 200, type = 'item', image = 'obd_ghost.png', unique = false, useable = true, shouldClose = true, description = 'Unlabeled. No serial.' },
        obd_chip = { name = 'obd_chip', label = 'ECU Chip', weight = 50, type = 'item', image = 'obd_chip.png', unique = false, useable = false, shouldClose = false, description = 'Single use' }
    },
    ox = {
        obd_scanner = { label = 'OBD-II Scanner', weight = 500, stack = false, close = true, consume = 0, server = { export = 'aw-obdsystem.scanner' } },
        obd_ghost = { label = 'Modified OBD Dongle', weight = 200, stack = false, close = true, consume = 0, server = { export = 'aw-obdsystem.ghost' } },
        obd_chip = { label = 'ECU Chip', weight = 50 }
    }
}
