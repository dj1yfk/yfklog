-- Change YFKlog to your database name, if different 

USE YFKlog; 

CREATE TABLE `calls` (
  `CALL` varchar(12) NOT NULL default '',
  `NAME` varchar(12) default '',
  `QTH` varchar(15) default '',
  PRIMARY KEY  (`CALL`)
) TYPE=MyISAM;

CREATE TABLE clubs (
  `club` varchar(30) NOT NULL default '',
  `nr` varchar(6) NOT NULL default '',
  `call` varchar(6) NOT NULL default ''
) TYPE=MyISAM;

