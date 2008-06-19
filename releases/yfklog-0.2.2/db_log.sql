# This is the SQL code to generate a new logbook table in the database.
# Logbooks can be created manually or more comfortable under the menu item
# "Logbook config" in YFKlog.
  
CREATE TABLE `log_MYCALL` (
  `NR` bigint(20) NOT NULL auto_increment,
  `CALL` varchar(15) NOT NULL default '',
  `DATE` date NOT NULL default '0000-00-00',
  `T_ON` time NOT NULL default '00:00:00',
  `T_OFF` time NOT NULL default '00:00:00',
  `BAND` float unsigned NOT NULL default '0',
  `MODE` varchar(6) NOT NULL default '',
  `QTH` varchar(15) default '',
  `NAME` varchar(15) default '',
  `QSLS` char(1) NOT NULL default '',
  `QSLR` char(1) NOT NULL default '',
  `RSTS` int(10) unsigned NOT NULL default '599',
  `RSTR` int(10) unsigned NOT NULL default '599',
  `REM` varchar(60) default '',
  `PWR` int(10) unsigned default '0',
  `DXCC` varchar(4) NOT NULL default '',
  `PFX` varchar(8) NOT NULL default '',
  `CONT` char(3) NOT NULL default '',
  `ITUZ` int(2) unsigned NOT NULL default '0',
  `CQZ` int(2) unsigned NOT NULL default '0',
  `QSLINFO` varchar(15) default '',
  `IOTA` varchar(6) default '',
  `STATE` varchar(2) default '',
  PRIMARY KEY  (`NR`),
  KEY `CALL` (`CALL`),
  KEY `DXCC` (`DXCC`)
) TYPE=MyISAM AUTO_INCREMENT=1 ;
