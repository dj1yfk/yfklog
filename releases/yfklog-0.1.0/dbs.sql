-- Change DJ1YFK to your database name! 

USE yfklog; 

CREATE TABLE `calls` (
  `CALL` varchar(8) NOT NULL default '',
  `NAME` varchar(12) default '',
  `QTH` varchar(15) default '',
  PRIMARY KEY  (`CALL`)
) TYPE=MyISAM;

CREATE TABLE clubs (
  club varchar(30) NOT NULL default '',
  nr varchar(6) NOT NULL default '',
  call varchar(6) NOT NULL default ''
) TYPE=MyISAM;

