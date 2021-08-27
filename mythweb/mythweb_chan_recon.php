<?php
/**
 Copyright 2021 Myers Enterprises II
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 
 Installation:
   copy this file to /var/www/html/mythweb/
   sudo apt install php-sqlite3
 
 Configuration:
   In /etc/apache2/sites-available/mythweb.conf change <Files mythweb.*> to <Files mythweb*.p*>
   sudo service apache2 restart
   sudo chmod a+w /home/mythtv/.xmltv
   sudo chmod a+w /home/mythtv/.xmltv/SchedulesDirect.DB
   
 */
?>
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml">
    <head>
	    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	    <title>MythTV Channel Reconciliation</title>
	    <script type='text/javascript' src='js/prototype.js'></script>
	    <script type='text/javascript' src='js/table_sort.js'></script>
	</head>
	<body>
	<h1>MythTV Channel Reconciliation</h1>
<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE | E_NOTICE);
ini_set("display_errors", 1);

$slconn = new PDO('sqlite:/home/mythtv/.xmltv/SchedulesDirect.DB');
$slconn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$msconn = new PDO("mysql:host={$_SERVER['db_server']};dbname={$_SERVER['db_name']};charset=utf8", $_SERVER['db_login'], $_SERVER['db_password']);
$msconn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

// Load mythtv channel table
$sql = 'SELECT * FROM channel ORDER BY chanid';
$sth = $msconn->query($sql);
$sth->setFetchMode(PDO::FETCH_NAMED);
$myth_channels = [];

while ($row = $sth->fetch()) {
    $channum = $row['channum'];
    if (strpos($channum, '_') === false) continue; // Analog
    if ($channum[0] == '_') continue; // Borked
    
    list($chan, $sub) = explode('_', $channum);
    $channum = "$chan.$sub";
    $row['XMLTV_selected'] = 'missing';
    $row['channum'] = $channum;
    
    $myth_channels[$channum] = $row;
}

// Load the XMLTV channels, stations tables
$sql = 'SELECT channum, selected FROM channels';
$sth = $slconn->query($sql);
$sth->setFetchMode(PDO::FETCH_NAMED);

while ($row = $sth->fetch()) {
    $channum = $row['channum'];
    if (strpos($channum, '.') === false) continue; // Analog
    
    if (! isset($myth_channels[$channum])) continue;
    $myth_channels[$channum]['XMLTV_selected'] = $row['selected'];
}
    
uasort($myth_channels, function ($a, $b) {
    list($achan, $asub) = explode('.', $a['channum']);
    list($bchan, $bsub) = explode('.', $b['channum']);
    
    if ($achan != $bchan) return ($achan <=> $bchan);
    return ($asub <=> $bsub);
});

?>
<table id="channel_list" sortable=true>
<thead><tr><th>channum</th><th>freqid</th><th>name</th><th>visible</th><th>XMLTV<br />selected</th></tr></thead><tbody>
<?php
$prev_freq = '';

foreach ($myth_channels as $channum => $chan) {
    $rowcolor = '';
    if ($chan['visible'] != $chan['XMLTV_selected']) $rowcolor = ' style="background-color:#eee8e0;"';
    
    $freq = $chan['freqid'];
    
    if ($freq != $prev_freq) $prev_freq = $freq;
    else $freq = '&nbsp';
    
    $name = $chan['name'];
    if (preg_match('!^\d+\.\d+ (.*)$!', $name, $matches)) {
        $name = $matches[1];
    }
    
    echo "<tr$rowcolor><td>$channum</td><td>$freq</td><td>$name</td><td style='text-align: center;'>{$chan['visible']}</td><td style='text-align: center;'>{$chan['XMLTV_selected']}</td></tr>\n";
}
?>
</tbody>
</table>
</body>
