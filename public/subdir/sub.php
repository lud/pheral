<?php


$keys = ['SCRIPT_NAME','SCRIPT_FILENAME','PATH_TRANSLATED','PHP_SELF','REQUEST_URI', 'REQUEST_METHOD', 'PATH_INFO'];
echo "<pre>\n";
foreach ($keys as $key) {

	$inspected = isset($_SERVER[$key])
		? var_export($_SERVER[$key], true)
		: ' -- NOT SET --';
	echo str_pad($key, 15 ), ' ', $inspected , PHP_EOL;
}
if (isset($_GET['server'])) {
	var_dump($_SERVER);
}
echo "</pre>\n";

if (isset($_GET['phpinfo'])) {
	phpinfo();
}

if (! in_array($_SERVER['REQUEST_METHOD'], ['GET', 'DELETE', 'OPTIONS', 'HEAD'])) {
	$reqBody = file_get_contents('php://input');
	$reqData = json_decode($reqBody, 1);
	var_dump($reqData);
	if (isset(${'_' . $_SERVER['REQUEST_METHOD']})) {
		var_dump(${'_' . $_SERVER['REQUEST_METHOD']});
	}
}
