# Unfortunately the AGCW membership data is only available as a Excel
# spreadsheet. It needs to be converted to a CSV list.

BEGIN {
		print "use YFKlog;"
}

// {
	split($0,array,";")			# split the line up
	print "INSERT INTO clubs (CLUB, CALL, NR) VALUES ('AGCW', '"array[2]"', '"array[1]"');"
}	

