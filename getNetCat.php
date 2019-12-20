<?php
error_reporting(0);
require_once './conf_settings.php';
require_once './admin_netcat.php';

// Get info from NetCat for wireless devices
$netcatStr = netcat::getClientDetails($NCconfig['host'], $NCconfig['port'], filter_input(INPUT_SERVER, 'REMOTE_ADDR'), true);
//If status=notFound it's probably not a wireless device
echo (strstr($netcatStr, "notFound") === false) ? $netcatStr : "";
