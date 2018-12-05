<?php


$keys = ['SCRIPT_NAME','SCRIPT_FILENAME','PATH_TRANSLATED','PHP_SELF','REQUEST_URI'];
echo '<pre>';
foreach ($keys as $key) {
	echo str_pad($key, 15 ), ' ', var_export($_SERVER[$key], true), PHP_EOL;
}
if (isset($_GET['server'])) {
	var_dump($_SERVER);
}
echo '</pre>';

if (isset($_GET['phpinfo'])) {
	phpinfo();
}
