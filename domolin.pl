#!/usr/bin/env perl

use Mojolicious::Lite;
use Device::BCM2835;
use strict;

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
get '/on/:pinNumber' => [pinNumber => qr/\d+/] => sub {
	my $c = shift;
	my $pinNumber = $c->param('pinNumber');

	# Check that the pinNumber is valid and throw a 500 error if not
	return $c->reply->exception("Error: The pin number $pinNumber is not available") 
		unless ($pinNames[$pinNumber]);

	setPinAsOutput($pinNumber);
	pinH($pinNumber);
	my $output=readAllPins();	
	$c->render(json => $output);
};

get '/off/:pinNumber' => [pinNumber => qr/\d+/] => sub {
	my $c = shift;
	my $pinNumber = $c->param('pinNumber');

	# Check that the pinNumber is valid and throw a 500 error if not
	return $c->reply->exception("Error: The pin number $pinNumber is not available") 
		unless ($pinNames[$pinNumber]);

	setPinAsOutput($pinNumber);
	pinL($pinNumber);
	my $output=readAllPins();	
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
	warn $pinName;
	Device::BCM2835::gpio_fsel(eval('&Device::BCM2835::'.$pinName),&Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);
	return;	
}
sub setPinAsInput {
	my $pinNumber=shift;
	my $pinName=$pinNames[$pinNumber];
	warn $pinName;
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
