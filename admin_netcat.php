<?php

class netcat {
    /**
     * Equal to the command:
     * echo $ip | nc -u myHOST.myDOMAIN 23456 -w10
     *
     * Returns error string or result array (can be empty)
     *
     */
    public static function getClientDetails($host, $port, $ip, $raw = false) {
        //Create socket
        if(!($sock = socket_create(AF_INET, SOCK_DGRAM, 0)))
        {
            // perror("Could not create socket");
            return "";
        }

        //Connect socket to remote server
        if(!socket_connect($sock , $host, $port))
        {
            // perror("Could not connect");
            return "";
        }

        //Send the message to the server
        if( ! socket_send($sock , $ip , strlen($ip) , 0))
        {
            // perror("Could not send data");
            return "";
        }

        //Now receive reply from server
        if(socket_recv($sock , $buf , 500 , MSG_WAITALL) === FALSE)
        {
            // perror("Could not receive data");
            return "";
        }

        //Close socket
        socket_close($sock);

        return (!$raw) ? self::parseResult($buf) : $buf;
    }

    public static function getClientDetailsAndSendSpeedtest($host, $port, $ip, $result, $raw = false) {
        //Create socket
        if(!($sock = socket_create(AF_INET, SOCK_DGRAM, 0)))
        {
            // perror("Could not create socket");
            return "";
        }

        //Connect socket to remote server
        if(!socket_connect($sock , $host, $port))
        {
            // perror("Could not connect");
            return "";
        }

        //Send the message to the server
        if( ! socket_send($sock , $ip , strlen($ip) , 0))
        {
            // perror("Could not send data");
            return "";
        }

        //Now receive reply from server
        if(socket_recv($sock , $buf , 500 , MSG_WAITALL) === FALSE)
        {
            // perror("Could not receive data");
            return "";
        }

        //Send the message to the server
        if( ! socket_send($sock , $result , strlen($result) , 0))
        {
            // perror("Could not send data");
            return "";
        }

        //Close socket
        socket_close($sock);

        return (!$raw) ? self::parseResult($buf) : $buf;
    }


    /**
     * Format speedtest result for UDP package
     */
    public static function formatSpeedtest($ip, $dl, $ul, $ping, $jitter) {
        return "IP=".$ip."; DL=".$dl."Mbps; UL=".$ul."Mbps; PING=".$ping."ms; JITTER=".$jitter."ms; ";
    }

    /**
     * Expected input format:
     * AP=tf-2396-01-rw; MAC=f4:0f:24:24:4b:57; MCS=7; PHY=ac (5GHz); RSSI=-68dBm; SNR=29dB; SS=3; SSID=eduroam; uptime=01:34:42;
     * OR
     * status=notFound
     *
     * Returns array
     */
    private static function parseResult($contents) {
        $resultArray = array();
        $index = -1;

        $result = explode(';', $contents);
        for ($i = 0; $i < count($result); $i++) {
            // Check length of string
            if (strlen($result[$i]) === 0 || strpos($result[$i], '=') === false) {
                continue;
            }
            // Explode to KEY VALUE
            list($key, $value) = explode('=', $result[$i]);
            // AP is the first KEY VALUE in a series of values
            if (trim($key) === "AP") {
                $index++;
                $resultArray[$index] = array();
            }
            $resultArray[$index][trim($key)] = trim($value);
        }

        return $resultArray;
    }

    public static function getClientDetailsJson($NCconfig, $ip) {
        return json_encode(self::getClientDetails($NCconfig, $ip));
    }

    public static function testParser() {
        return self::parseResult("AP=tf-2396-01-rw; MAC=f4:0f:24:24:4b:57; MCS=7; PHY=ac (5GHz); RSSI=-68dBm; SNR=29dB; SS=3; SSID=eduroam; uptime=01:34:42;AP=tf-2396-01-rw; MAC=f4:0f:24:24:4b:57; MCS=7; PHY=ac (5GHz); RSSI=-68dBm; SNR=29dB; SS=3; SSID=eduroam; uptime=01:34:42;");
        // return self::parseResult("AP=tf-2396-01-rw; MAC=f4:0f:24:24:4b:57; MCS=7; PHY=ac (5GHz); RSSI=-68dBm; SNR=29dB; SS=3; SSID=eduroam; uptime=01:34:42;");
    }

    ///Function to print socket error message
    private static function perror($msg)
    {
        $errorcode = socket_last_error();
        $errormsg = socket_strerror($errorcode);
        // Do nothing
        // die("$msg: [$errorcode] $errormsg \n");
    }
}

