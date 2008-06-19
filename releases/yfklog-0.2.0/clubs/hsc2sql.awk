# http://www.qsl.net/dl0hsc/files/hscmember.zip
#
# The HSC membership data is given in the following format:

# Call         HSC      Name                 2nd Call          ex Calls               Remarks
# -------------------------------------------------------------------------------------------------------
# 0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890
#           1         2         3         4         5         6         7         8
#
# What we need is only "Call", "HSC" (number) and "ex Calls" (2nd calls are
# included in the normal list already as multiple entries)

BEGIN {
		print "use YFKlog;"
}

/^[0-9A-Z]*[0-9]+/ {			# Line starts with a number or letter, 
								# then another number.. has to be a call
	# The first two are always a callsign/number 
	# combination and can be added to the DB.

	print "INSERT INTO clubs (CLUB, CALL, NR) VALUES ('HSC', '"$1"', '"$2"');"
		
	# Now of the remaining line, we are only interested in 60 .. 83 (ex Calls)
	# we save the part in question in "line", omitting the last character
	# (newline).
	line = substr($0, 60, length($0)-60);
	gsub(/(\s|,)+/," ", line);			# remove all whitespaces and commas
	if (length(line) > 1) {				# we have a ex Call
		split(line, array, " ");		# split line into array
		for (foo in array) {			# for every callsign
			# print the callsign and the number...
			print "INSERT INTO clubs (CLUB, CALL,NR) VALUES ('HSC', '"array[foo]"', '"$2"');"
		}
	}
}
