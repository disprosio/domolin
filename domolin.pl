#!/usr/bin/env perl

use Mojolicious::Lite;
use Device::BCM2835;
use JSON::Parse 'parse_json';

my $config = plugin 'Config';

Device::BCM2835::init() || die "Could not init library";

my @pinNames=(undef,
 "RPI_GPIO_P1_11", "RPI_GPIO_P1_12",
 "RPI_GPIO_P1_13", "RPI_GPIO_P1_15",
 "RPI_GPIO_P1_16", "RPI_GPIO_P1_18",
 "RPI_GPIO_P1_22", "RPI_GPIO_P1_07");

sub startup {
	my $c = shift;
	$c->plugin('Config');
}


get '/' => sub {
	my $c = shift;
	# To read the custom headers passed by the application 
 	# on the request use the following:
	#	 
 	my $authToken = $c->req->headers->{headers}->{'auth-token'}[0];
 
	my $output=readAllPins();	
	$c->render(json => $output);
};

# Local system routes
get '/:operation/:pinNumber' => [operation => ['on', 'off'], pinNumber => qr/\d+/] => sub {
        my $c = shift;
        my $pinNumber = $c->param('pinNumber');
        my $operation = $c->param('operation');

	# Check that the pinNumber is valid and throw a 500 error if not
	return $c->reply->exception("Error: The pin number $pinNumber is not available")
		unless ($pinNames[$pinNumber]);
	
	setPinAsOutput($pinNumber);
	if ($operation eq "on") {
		pinH($pinNumber);
	} else {
		pinL($pinNumber);
	}
	my $output=readAllPins();
	$c->render(json => $output);
};

# Remote system routes
get '/remote/:remoteName/:operation/:pinNumber' => [operation => ['on', 'off'], pinNumber => qr/\d+/] => sub {
	my $c = shift;
	my $remoteName = $c->param('remoteName');
	my $operation = $c->param('operation');
        my $pinNumber = $c->param('pinNumber');

	# Check that the remoteName is valid and throw a 500 error if not
        return $c->reply->exception("Error: The remote system $remoteName is not available")
		unless($config->{remoteSystems}->{$remoteName});
        if ($operation eq "on") {
		remotePinH($remoteName,$pinNumber);
        } else {
		remotePinL($remoteName,$pinNumber);
        }
	my $output=readAllRemotePins($remoteName);
	$c->render(json => $output);
};

get '/allOn' => sub {
	my $c = shift;
	allPinsOn();
	my $output=readAllPins();	
	$c->render(json => $output);
};

get '/allOff' => sub {
	my $c = shift;
	allPinsOff();
	my $output=readAllPins();	
	$c->render(json => $output);
};

get '/info' => sub {
	my $c = shift;
	$c->render("info");		
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
	my @output;
	for my $pinNumber (1..8) {
		my $pinOutput;
		$pinOutput->{pin}=$pinNumber;
		$pinOutput->{status}=pinRead($pinNumber);
		push(@output,$pinOutput);
	}
	return \@output;
}

sub readAllRemotePins {
	my $remoteName = shift;
	my $remoteAddress = $config->{remoteSystems}->{$remoteName}->{address};
	my $remoteUrl = $remoteAddress;
	my $output = `curl -s $remoteUrl`;
	my $jsonOutput = parse_json($output);
	return $jsonOutput;
}

sub remotePinH {
	my $remoteName=shift;
	my $pinNumber=shift;
 	my $remoteAddress = $config->{remoteSystems}->{$remoteName}->{address};
	my $remoteUrl = $remoteAddress.'/on/'.$pinNumber;
	my $output = `curl -s $remoteUrl`;
	return;
}


sub remotePinL {
	my $remoteName=shift;
	my $pinNumber=shift;
 	my $remoteAddress = $config->{remoteSystems}->{$remoteName}->{address};
	my $remoteUrl = $remoteAddress.'/off/'.$pinNumber;
	my $output = `curl -s $remoteUrl`;
	return;
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
    <pre><%= dumper $config %></pre>
  </body>
</html>
