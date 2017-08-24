#!/usr/bin/env perl

use Mojolicious::Lite;
use Device::BCM2835;
use JSON::Parse 'parse_json';
use WWW::Curl::Easy;
use Data::Dumper;

my $config = plugin 'Config';
my ($change, $activeConnections);

Device::BCM2835::init() || die "Could not init library";

my @pinNames=(undef,
 "RPI_GPIO_P1_11", "RPI_GPIO_P1_12",
 "RPI_GPIO_P1_13", "RPI_GPIO_P1_15",
 "RPI_GPIO_P1_16", "RPI_GPIO_P1_18",
 "RPI_GPIO_P1_22", "RPI_GPIO_P1_07");

app->plugin('Config');

# Global logic shared by all routes to send a cors header by dfault
under sub {
	my $c = shift;
	$c->res->headers->header('Access-Control-Allow-Origin' => '*');
};

get '/' => sub {
	my $c = shift;
	# To read the custom headers passed by the application 
 	# on the request use the following:
	#	 
 	my $authToken = $c->req->headers->{headers}->{'auth-token'}[0];
 
	$c->render(text => "");
};


#############################
# Local system routes
#############################
get '/:operation/:pinNumber' => [operation => ['on', 'off'], pinNumber => qr/\d+/] => sub {
        my $c = shift;
        my $pinNumber = $c->param('pinNumber');
        my $operation = $c->param('operation');

	# Check that the pinNumber is valid and return the error if not
	return $c->render(json => {error=> "The pin number $pinNumber is not available"})
		unless ($pinNames[$pinNumber]);
	
	setPinAsOutput($pinNumber);
	if ($operation eq "on") {
		pinH($pinNumber);
	} else {
		pinL($pinNumber);
	}
	my $output=readAllSystems();

	$change=$output;
	$c->app->log->info("Action $operation on pin $pinNumber of local system from ". $c->tx->original_remote_address);
	$activeConnections=flagClients($activeConnections);
	$c->render(json => $output);
};

get '/allOn' => sub {
	my $c = shift;
	allPinsOn();
	my $output=readAllSystems();
	$change=$output;
	$activeConnections=flagClients($activeConnections);
	$c->render(json => $output);
};

get '/allOff' => sub {
	my $c = shift;
	allPinsOff();
	my $output=readAllSystems();
	$change=$output;
	$activeConnections=flagClients($activeConnections);
	$c->render(json => $output);
};

get '/status' => sub {
	my $c = shift;
	my $output=readAllPins();	
	$c->render(json => $output);
};

get '/info' => sub {
	my $c = shift;
	my $infoOutput;
	$infoOutput->{localSystem}=$config->{localSystem};
	$infoOutput->{remoteSystems}=$config->{remoteSystems};
	$c->respond_to(
	     json => {json => $infoOutput},
	     html => {template => "info", infoOutput => $infoOutput},
	);
};


#############################
# Remote system routes
#############################
get '/remote/:remoteName/:operation/:pinNumber' => [operation => ['on', 'off'], pinNumber => qr/\d+/] => sub {
	my $c = shift;
	my $remoteName = $c->param('remoteName');
	my $operation = $c->param('operation');
        my $pinNumber = $c->param('pinNumber');

	# Check that the remoteName is valid and return errors if not
	return $c->render(json => {error=> "The remote system $remoteName is not available"})
		unless($config->{remoteSystems}->{$remoteName});
	
	my ($result,$output);
        if ($operation eq "on") {
		($result,$output)=remotePinH($remoteName,$pinNumber);
        } else {
		($result,$output)=remotePinL($remoteName,$pinNumber);
        }
	# Return a 500 error if the remote request did not go well
	return $c->render(json => {error=> "The remote system $remoteName returned the error $output"})
		unless($result==0);

	$output=readAllSystems();	
	$c->app->log->info("Action $operation on pin $pinNumber of remote system $remoteName");
	$change = $output;
	$activeConnections=flagClients($activeConnections);
	$c->render(json => $output);
};


get '/statusAll' => sub {
	my $c = shift;
	my ($error,$output)=readAllSystems();	
	if ($error) {
		$output = {error=> $output};
	}
	$c->render(json => $output);	
};


#############################
# Websockets routes
#############################
websocket '/realTime' => sub {
	my $c = shift;
	$c->inactivity_timeout(3600);

	$c->on( message => sub {
		my $connection = $c->tx->connection;
		my $remoteIp=$c->tx->remote_address;
		my $userAgent = $c->tx->req->headers->user_agent;
  		$c->app->log->info("New connection $connection from $remoteIp $userAgent");
		$activeConnections->{$connection}->{changed}=0;
		$c->send({ json => $change }) ;
	});


  	my $timer = Mojo::IOLoop->recurring( 1 => sub {
		if ($change) {
			my $connection = $c->tx->connection;
	  		$c->app->log->debug("There is a change:". Dumper($change));
			if ($activeConnections->{$connection}->{toChange}){
		  		$c->app->log->debug("Sending change to $connection");
				$c->send({ json => $change });
				$activeConnections->{$connection}->{toChange}=0;			
			}
	  		$c->app->log->debug("Active connections: ". Dumper($activeConnections));
			my $newChange=0;
			foreach my $activeConn (keys(%{$activeConnections})) {
				$newChange+=$activeConnections->{$activeConn}->{toChange};
			}
			undef($change) if ($newChange==0);
		}
	});

	$c->on( finish => sub {
		my $connection = $c->tx->connection;
		my $remoteIp=$c->tx->original_remote_address;
  		$c->app->log->info("Removing connection $connection from $remoteIp");
		Mojo::IOLoop->remove($timer);
	});

};

app->start;


###############################################################################################
# Functions
###############################################################################################


sub pinRead {
	my $pinNumber=shift;
	my $pinName=$pinNames[$pinNumber];
	my $value=Device::BCM2835::gpio_lev(eval('&Device::BCM2835::'.$pinName));
	return $value;
}

sub pinH {
	my $pinNumber=shift;
	my $pinName=$pinNames[$pinNumber];
	Device::BCM2835::gpio_write(eval('&Device::BCM2835::'.$pinName), 1);
	return;
}

sub pinL {
	my $pinNumber=shift;
	my $pinName=$pinNames[$pinNumber];
	Device::BCM2835::gpio_write(eval('&Device::BCM2835::'.$pinName), 0);
	return;
}

sub readAllPins {
	my $output;
	for my $pinNumber (1..8) {
		my $pinOutput;
		$pinOutput->{pin}=$pinNumber;
		$pinOutput->{status}=pinRead($pinNumber);
		$output->{$pinNumber}=$pinOutput;
	}
	return $output;
}

sub readAllRemotePins {
	my $remoteName = shift;
	my $remoteAddress = $config->{remoteSystems}->{$remoteName}->{address};
	my $remoteUrl = $remoteAddress."/status";
	
	my $responseBody;

	my $curl = WWW::Curl::Easy->new;
	$curl->setopt(CURLOPT_URL, $remoteUrl);
	$curl->setopt(CURLOPT_WRITEDATA,\$responseBody);

	my $retCode = $curl->perform;
	my $responseCode = $curl->getinfo(CURLINFO_HTTP_CODE);

	# Error checking
	return(1,"Error in remote system $remoteName: $retCode ".$curl->strerror($retCode))
		unless ($retCode == 0);

	return(1,"Error in remote system $remoteName: $responseCode ")
		unless ($responseCode == 200);

	return(1,"Error in remote system $remoteName: No valid response ")
		unless ($responseBody ne "");

	# All clean, no errors, return the json
	my $jsonOutput = parse_json($responseBody);
	return (0,$jsonOutput);
}

sub readAllSystems {
	my $outputAll;
	
	# Read local pins
	my $localOutput=readAllPins();
	$outputAll->{"local"}=$localOutput;

	# Read all remote systems	
	if ($config->{remoteSystems}) {
		my @remoteSystemsNames = keys($config->{remoteSystems});
		foreach my $remoteName (@remoteSystemsNames) {
			my ($error, $output) = readAllRemotePins($remoteName);
			return(1,$output)
				unless ($error == 0);
			$outputAll->{$remoteName}=$output;
		}		
	}
	return (0,$outputAll);
}


sub remotePinH {
	my $remoteName=shift;
	my $pinNumber=shift;
 	my $remoteAddress = $config->{remoteSystems}->{$remoteName}->{address};
	my $remoteUrl = $remoteAddress.'/on/'.$pinNumber;
	my $responseBody;

	my $curl = WWW::Curl::Easy->new;
	$curl->setopt(CURLOPT_URL, $remoteUrl);
	$curl->setopt(CURLOPT_WRITEDATA,\$responseBody);

	my $retCode = $curl->perform;
	my $responseCode = $curl->getinfo(CURLINFO_HTTP_CODE);

	# Error checking
	return(1,"Error in remote system $remoteName: $retCode ".$curl->strerror($retCode))
		unless ($retCode == 0);

	return(1,"Error in remote system $remoteName: $responseCode ")
		unless ($responseCode == 200);

	return(1,"Error in remote system $remoteName: No valid response ")
		unless ($responseBody ne "");

	# All clean, no errors, return the json
	my $jsonOutput = parse_json($responseBody);
	return (0,$jsonOutput);
}


sub remotePinL {
	my $remoteName=shift;
	my $pinNumber=shift;
 	my $remoteAddress = $config->{remoteSystems}->{$remoteName}->{address};
	my $remoteUrl = $remoteAddress.'/off/'.$pinNumber;
	my $responseBody;

	my $curl = WWW::Curl::Easy->new;
	$curl->setopt(CURLOPT_URL, $remoteUrl);
	$curl->setopt(CURLOPT_WRITEDATA,\$responseBody);

	my $retCode = $curl->perform;
	my $responseCode = $curl->getinfo(CURLINFO_HTTP_CODE);

	# Error checking
	return(1,"Error in remote system $remoteName: $retCode ".$curl->strerror($retCode))
		unless ($retCode == 0);

	return(1,"Error in remote system $remoteName: $responseCode ")
		unless ($responseCode == 200);

	return(1,"Error in remote system $remoteName: No valid response ")
		unless ($responseBody ne "");

	# All clean, no errors, return the json
	my $jsonOutput = parse_json($responseBody);
	return (0,$jsonOutput);
}

sub allPinsOn {
	for(1..8) {
		setPinAsOutput($_);
		pinH($_);
	}
	return;
}

sub allPinsOff {
	for(1..8) {
		setPinAsOutput($_);
		pinL($_);
	}
	return;
}

sub setPinAsOutput {
	my $pinNumber=shift;
	my $pinName=$pinNames[$pinNumber];
	Device::BCM2835::gpio_fsel(eval('&Device::BCM2835::'.$pinName),&Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);
	return;	
}
sub setPinAsInput {
	my $pinNumber=shift;
	my $pinName=$pinNames[$pinNumber];
	Device::BCM2835::gpio_fsel(eval('&Device::BCM2835::'.$pinName),&Device::BCM2835::BCM2835_GPIO_FSEL_INPT);
	return;	
}

sub flagClients {
	my $activeConnections = shift;
	foreach my $connection (keys %{$activeConnections}) {
		$activeConnections->{$connection}->{toChange}=1;
	}
	return($activeConnections);
};
 
__DATA__


@@ exception.production.html.ep
<!DOCTYPE html>
<html>
  <head><title>Server error</title></head>
  <body>
    <h1>Application error</h1>
    <p><%= $exception->message %></p>
  </body>
</html>

@@ not_found.production.html.ep
<!DOCTYPE html>
<html>
  <head><title>Method not implemented</title></head>
  <body>
    <h1>Method not implemented</h1>
  </body>
</html>
 

@@ info.html.ep
<!DOCTYPE html>
<html>
  <head><title>Domolín Application Info</title></head>
  <style>* { font-family:Arial}</style>
  <body>
    <h1>Domolín Application Info</h1>
    <h2>LocalSystem</h2>
    <pre>
    <%= dumper $infoOutput->{localSystem} %>
    </pre>
    <h2>RemoteSystem</h2>
    <pre>
    <%= dumper $infoOutput->{remoteSystems} %>
    </pre>
  </body>
</html>
