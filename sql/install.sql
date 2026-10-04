CREATE TABLE IF NOT EXISTS `aw_obd_vehicles` (
    `plate` VARCHAR(12) NOT NULL,
    `mileage` INT NOT NULL DEFAULT 0,
    `stolen` TINYINT(1) NOT NULL DEFAULT 0,
    `tamper` INT NOT NULL DEFAULT 0,
    `last_tamper` VARCHAR(32) DEFAULT NULL,
    `last_tamper_at` INT DEFAULT NULL,
    `history` LONGTEXT DEFAULT NULL,
    PRIMARY KEY (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `items` (`name`, `label`, `weight`) VALUES
    ('obd_scanner', 'OBD-II Scanner', 1),
    ('obd_ghost', 'Modified OBD Dongle', 1),
    ('obd_chip', 'ECU Chip', 1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
