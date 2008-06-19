<!-- For testing only :)  --> 

<?php $callsign = $_GET["callsign"]; 
if (!$callsign) { $callsign = "DJ1YFK"; }		
$callsign = strtoupper($callsign);
?>

<html>
<head>
	<title>Online Log result for <?php echo $callsign; ?></title>
</head>

<h1>Search!</h1>

<form action="search.php" method="GET">

<input name="callsign" type="text" value="<?php echo $callsign; ?>" size="15"
	maxlength="15">
<input type="submit" value=" check "> 
</form>


<h1>Results for <?php echo $callsign; ?></h1>

<table border="1">
<?php 
$qsos = file("test.txt");
foreach ($qsos as $qso) {
	if (ereg($callsign, $qso)) {				# line contains the call
		echo "<tr>";
		$data = explode('~', $qso);				# put stuff in $data
		foreach ($data as $foo) {				# every data..
			echo "<td>$foo</td>";
		}
		echo "</tr>\n";
	}
}
?>
</table>

		
