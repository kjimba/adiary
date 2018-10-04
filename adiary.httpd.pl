#!/usr/bin/perl
use 5.8.1;
use strict;
###############################################################################
# Satsuki system - HTTP Server
#						Copyright (C)2018 nabe@abk
###############################################################################
# Last Update : 2018/09/xx
#
BEGIN {
	my $path = $0;
	$path =~ s|/[^/]*||;
	if ($path) { chdir($path); }
	unshift(@INC, './lib');
}
use Socket;
use Fcntl;
use threads;		# for ithreads
use POSIX;		# for waitpid(<pid>, WNOHANG);
use Cwd;		# for $ENV{DOCUMENT_ROOT}
use Time::HiRes;	# for generate random string
use Image::Magick;	# load on main process for Windows EXE
use Encode::Locale;	# for get system locale / for Windows
#------------------------------------------------------------------------------
use Satsuki::Base ();
use Satsuki::AutoReload ();
&Satsuki::AutoReload::save_lib();
###############################################################################
# setting
###############################################################################
my $SILENT_CGI   = 0;
my $SILENT_FILE  = 0;
my $SILENT_OTHER = 0;
my $IsWindows = ($^O eq 'MSWin32');

my $PORT    = $IsWindows ? 80 : 8888;
my $ITHREAD = $IsWindows;
my $PATH    = $ARGV[0];
my $TIMEOUT = 1;
my $DEAMONS = 5;
my $MIME_FILE = '/etc/mime.types';
my $INDEX;  # = 'index.html';

my $SYS_CODE = $Satsuki::SYSTEM_CODING;
my $FS_CODE  = $IsWindows ? $Encode::Locale::ENCODING_LOCALE : undef;

# select() is thread block on Windows
my $SELECT_TIMEOUT = $IsWindows ? 0.01 : undef;
#------------------------------------------------------------------------------
my %DENY_DIRS;
my %MIME_TYPE = ( 
	html => 'text/html',
	htm  => 'text/html',
	text => 'text/plain',
	txt  => 'text/plain',
	css  => 'text/css',
	js   => 'application/javascript',
	json => 'application/json',
	xml  => 'application/xml',
	png  => 'image/png',
	jpg  => 'image/jpeg',
	jpeg => 'image/jpeg'
);
my %DENY_EXTS = (cgi=>1, pl=>1, pm=>1);	# deny extensions
#------------------------------------------------------------------------------
# for RFC date
#------------------------------------------------------------------------------
my %JanFeb2Mon = (
	Jan => 0, Feb => 1, Mar => 2, Apr => 3, May => 4, Jun => 5,
	Jul => 6, Aug => 7, Sep => 8, Oct => 9, Nov =>10, Dec =>11
);
#------------------------------------------------------------------------------
# analyze @ARGV
#------------------------------------------------------------------------------
{
	my @ary = @ARGV;
	my $help;
	while(@ary) {
		my $key = shift(@ary);
		if (substr($key, 0, 1) ne '-') { $help=1; last; }
		$key = substr($key, 1);
		my @c = split('', $key);
		while(@c) {
			my $k = shift(@c);
			if ($k eq 'h') { $help =1; next; }
			if ($k eq '?') { $help =1; next; }
			if ($k eq 'i') { $ITHREAD=1; next; }
			if ($k eq 'f') { $ITHREAD=0; next; }

			# silent
			if ($k eq 's' && $c[0] eq 'c') { shift(@c); $SILENT_CGI  = $SILENT_OTHER = 1; next; }
			if ($k eq 's' && $c[0] eq 'f') { shift(@c); $SILENT_FILE = $SILENT_OTHER = 1; next; }
			if ($k eq 's') { $SILENT_CGI = $SILENT_FILE = $SILENT_OTHER = 1; next; }

			# arg
			if ($k eq 'p') { $PORT      = int(shift(@ary)); next; }
			if ($k eq 't') { $TIMEOUT   = int(shift(@ary)); next; }
			if ($k eq 'd') { $DEAMONS   = int(shift(@ary)); next; }
			if ($k eq 'm') { $MIME_FILE = shift(@ary); next; }
			if ($k eq 'c') { $FS_CODE   = shift(@ary); next; }
		}
	}
	if ($TIMEOUT < 1) { $TIMEOUT=1; }
	if ($DEAMONS < 1) { $DEAMONS=1; }
	
	if ($help) {
		print <<HELP;
Usage: $0 [options] [output_xml_file]
Available options are:
  -p port	bind port (default:8888, windows:80)
  -t timeout	connection timeout second (default:10)
  -m mime_file	load mime types file name (default: /etc/mime.types)
  -d deamons	start deamons (default:5), minimum 1
  -c fs_code	set file system's code
  -f		use fork()
  -i 		use threads (ithreads)
  -s            silent mode
  -sc           silent mode for cgi  access
  -sf           silent mode for file access
  -\?|-h		view this help
HELP
		exit(0);
	}
}
###############################################################################
# start up
###############################################################################
#------------------------------------------------------------------------------
# safety (Do not run on CGI/HTTP SERVER)
#------------------------------------------------------------------------------
$ENV{SERVER_PROTOCOL} && die "Do not run on CGI/HTTP SERVER";
#------------------------------------------------------------------------------
# ENV setting
#------------------------------------------------------------------------------
if (!$IsWindows) {
	foreach(keys(%ENV)) {
		if ($_ =~ /^Satsuki/) { next; }
		delete $ENV{$_};
	}
}
$ENV{GATEWAY_INTERFACE} = 'CGI/1.1';
$ENV{SCRIPT_NAME}     = $0;
$ENV{SERVER_NAME}     = 'localhost';
$ENV{SERVER_PORT}     = $PORT;
$ENV{SERVER_PROTOCOL} = 'HTTP/1.1';
$ENV{SERVER_SOFTWARE} = 'Satsuki';
$ENV{REQUEST_SCHEME}  = 'http';
$ENV{DOCUMENT_ROOT}   = Cwd::getcwd();
#------------------------------------------------------------------------------
# bind port
#------------------------------------------------------------------------------
my $srv;
{
	socket($srv, PF_INET, SOCK_STREAM, 0)				|| die "socket failed: $!";
	setsockopt($srv, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))	|| die "setsockopt failed: $!";
	bind($srv, sockaddr_in($PORT, INADDR_ANY))			|| die "bind port failed: $!";
	listen($srv, SOMAXCONN)						|| die "listen failed: $!";
}
print "Satsuki HTTP Server: Listen $PORT port, timeout $TIMEOUT sec\n";
print "\tStart up deamons: $DEAMONS (" . ($ITHREAD ? 'threads' : 'fork') . " mode)\n";

#------------------------------------------------------------------------------
# load mime types
#------------------------------------------------------------------------------
if ($MIME_FILE && -e $MIME_FILE) {
	print "\tLoad mime types: $MIME_FILE ";
	my $r = sysopen(my $fh, $MIME_FILE, O_RDONLY);
	if (!$r) {
		print "(error!)\n";
	} else {

		my $c=0;
		while(<$fh>) {
			chomp($_);
			my ($type, @ary) = split(/\s+/, $_);
			if ($type eq '' || !@ary) { next; }
			foreach(@ary) {
				$MIME_TYPE{$_} = $type;
				$c++;
			}
		}
		print "(load $c extensions)\n";
	}
	close($fh);
}

#------------------------------------------------------------------------------
# search deny directories
#------------------------------------------------------------------------------
{
	my @dirs = &search_dir_file('.htaccess');
	print "\tDeny dirs: " . join('/, ', @dirs) . "/\n";
	foreach(@dirs) {
		$DENY_DIRS{$_}=1;
	}
}

#------------------------------------------------------------------------------
if ($FS_CODE) {
	if ($FS_CODE =~ /utf-?8/i) { $FS_CODE='UTF-8'; }
	require Encode;
	print "\tSet file system coding: $FS_CODE\n";
}
if ($INDEX) {
	print "\tDirectory index: $INDEX\n";
}
($SILENT_CGI && $SILENT_FILE && $SILENT_OTHER) || print "\n";
###############################################################################
# main routine
###############################################################################
{
	local $SIG{CHLD};
	if (!$ITHREAD) {	# clear defunct process
		$SIG{CHLD} = sub {
			while(waitpid(-1, WNOHANG) > 0) {};
		};
	}

	# prefork
	for(my $i=0; $i<$DEAMONS; $i++) {
		&fork_or_crate_thread(\&deamon_main, $srv);
	}

	while(1) {
		sleep(100);
	}
}
close($srv);
exit(0);

sub deamon_main {
	my $srv  = shift;
	while(1) {
		my $addr = accept(my $sock, $srv);
		if (!$addr) { next; }
		&accept_client($sock, $addr);
	}
}

#------------------------------------------------------------------------------
# fork() or create->thread()
#------------------------------------------------------------------------------
sub fork_or_crate_thread {
	my $func = shift;
	if ($ITHREAD) {
		my $thr = threads->create($func, @_);
		if (!defined $thr) { die "threads->create fail!"; }
		$thr->detach();
		return;
	}
	# fork
	my $pid = fork();
	if (!defined $pid) {
		die "fork() fail!";
	}
	if (!$pid) {
		&$func(@_);
		exit();
	}
}

###############################################################################
# accept
###############################################################################
sub accept_client {
	my $sock = shift;
	my $addr = shift;
	my($port, $ip_bin) = sockaddr_in($addr);
	my $ip   = inet_ntoa($ip_bin);
	binmode($sock);

	$ENV{REMOTE_ADDR} = $ip;
	$ENV{REMOTE_PORT} = $port;

	my $state = &parse_request($sock);
	close($sock);

	&output_connection_log($state);
	return $state;
}
sub output_connection_log {
	my $state = shift;
	if (!$state) {
		$SILENT_OTHER || print "[$$] connection close\n";
	} else {
		if ($state->{type} eq 'file' && $SILENT_FILE
		 || $state->{type} eq 'cgi ' && $SILENT_CGI) {
			return;
 		}
		my $byte = $state->{send};
		print "[$$] $state->{status} $state->{type} " . (' ' x (7-length($byte))) . "$byte " . $state->{request} . "\n";
	}
}

#------------------------------------------------------------------------------
# parse request
#------------------------------------------------------------------------------
sub parse_request {
	my $sock  = shift;
	my $state = { sock => $sock, type=>'    ' };
	local(%ENV);

	#--------------------------------------------------
	# recieve HTTP Header
	#--------------------------------------------------
	my @header;
	{
		my $break;
		my $bad_req;

		local $SIG{ALRM} = sub { close($sock); $break=1; };
		alarm( $TIMEOUT );

		my $first=1;
		while(1) {
			my $line = &read_sock_1line($sock);		# no buffered <$sock>
			if (!defined $line)  {	# disconnect
				$break=1;
				last;
			}
			$line =~ s/[\r\n]//g;

			if ($first) {		# (example) HTTP/1.0 GET /
				$first = 0;
				$bad_req = &analyze_request($state, $line);
				if ($bad_req) { last; }
				next;
			}

			if ($line eq '') { last; }
			push(@header, $line);
		}

		alarm(0);
		if ($break)   { return; }
		if ($bad_req) { return $state; }
	}

	#--------------------------------------------------
	# Analyze Header
	#--------------------------------------------------
	foreach(@header) {
		if ($_ !~ /^([^:]+):\s*(.*)/) { next; }
		my $key = $1;
		my $val = $2;

		if ($key eq 'If-Modified-Since') {
			$state->{if_modified} = $val;
			next;
		}
		if ($key eq 'Content-Length') {
			$ENV{CONTENT_LENGTH} = $val;
			next;
		}
		if ($key eq 'Content-Type') {
			$ENV{CONTENT_TYPE} = $val;
			next;
		}

		$key =~ s/-/_/g;
		$key =~ tr/a-z/A-Z/;
		$ENV{"HTTP_$key"} = $val;
	}

	#--------------------------------------------------
	# file read
	#--------------------------------------------------
	my $path = $state->{path};
	$state->{file} = $path;
	$state->{file} =~ s/\?.*//;	# cut query
	$state->{file} =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;
	my $r = &try_file_read($state);
	if ($r) {
		return $state;
	}

	#--------------------------------------------------
	# Exec CGI
	#--------------------------------------------------
	$ENV{SERVER_NAME}    = $ENV{HTTP_HOST};
	$ENV{SERVER_NAME}    =~ s/:\d+$//;
	$ENV{REQUEST_METHOD} = $state->{method};
	$ENV{REQUEST_URI}    = $path;
	{
		my $x = index($path, '?');
		if ($x>0) {
			$ENV{QUERY_STRING} = substr($path, $x+1);
			$path = substr($path, 0, $x);
		}
	}
	$ENV{PATH_INFO} = $path;

	$state->{type} = 'cgi ';
	&exec_cgi($state);

	return $state;
}

#--------------------------------------------------
# Analyze Request
#--------------------------------------------------
sub analyze_request {
	my $state = shift;
	my $req   = shift;
	$state->{request} = $req;

	if ($req !~ m!^(GET|POST|HEAD) ([^\s]+) (?:HTTP/\d\.\d)?!) {
		&_400_bad_request($state);
		return 1;
	}

	my $method = $1;
	my $path   = $2;
	$state->{method} = $method;
	$state->{path}   = $path;
	if (substr($path,0,1) ne '/') {
		&_400_bad_request($state);
		return 2;
	}
	return 0;
}

#------------------------------------------------------------------------------
# try file read
#------------------------------------------------------------------------------
sub try_file_read {
	my $state = shift;
	my $file  = $state->{file};

	$file =~ s|/+|/|g;
	if ($file =~ m|/\.\./|) { return; }
	if ($INDEX ne '' && substr($file, -1) eq '/') {
		$file .= 'index.html';
	}
	$file = substr($file,1);	# /index.html to index.html

	#--------------------------------------------------
	# file system encode
	#--------------------------------------------------
	my $_file = $file;
	if ($FS_CODE && $FS_CODE ne $SYS_CODE) {
		Encode::from_to($_file, $SYS_CODE, $FS_CODE);
	}
	if (!-e $_file) { return; }

	#--------------------------------------------------
	# file request
	#--------------------------------------------------
	$state->{type} = 'file';
	if (!-r $_file
	 || $file =~ m|^\.ht|
	 || $file =~ m|/\.ht|
	 || $file =~ m|^([^/]+)/| && $DENY_DIRS{$1}) {
		&_403_forbidden($state);
		return 403;
	}
	# deny extensions
	while($file =~ /\.([^\.]+)/g) {
		if (! $DENY_EXTS{$1}) { next; }
		&_403_forbidden($state);
		return 403;
	}

	#--------------------------------------------------
	# header
	#--------------------------------------------------
	my $size = -s $_file;
	my $lastmod = &rfc_date( (stat $_file)[9] );
	my $header  = "Last-Modified: $lastmod\r\n";
	$header .= "Content-Length: $size\r\n";
	if ($file =~ /\.([\w\-]+)$/ && $MIME_TYPE{$1}) {
		$header .= "Content-Type: $MIME_TYPE{$1}\r\n";
	}
	if ($state->{if_modified} && $state->{if_modified} eq $lastmod) {
		&_304_not_modified($state, $header);
		return 304;
	}

	#--------------------------------------------------
	# read file
	#--------------------------------------------------
	sysopen(my $fh, $_file, O_RDONLY);
	my $r = sysread($fh, my $data, $size);
	if (!$fh || $r != $size) {
		&_403_forbidden($state);
		return 403;
	}
	close($fh);

	&_200_ok($state, $header, $data);
	return 200;
}

###############################################################################
# Exec CGI
###############################################################################
my @CGI;
sub exec_cgi {
	my $state = shift;
	my $cache = shift || 0;
	my $sock  = $state->{sock};

	my $ROBJ;
	eval {
		#--------------------------------------------------
		# connect stdout
		#--------------------------------------------------
		local *STDIN;
		open(STDIN,  '<&=', fileno($sock));
		binmode(STDIN);

		local *STDOUT;
		open(STDOUT, '>&=', fileno($sock));
		binmode(STDOUT);

		#--------------------------------------------------
		# update check
		#--------------------------------------------------
		my $flag = &Satsuki::AutoReload::check_lib();
		if ($flag) {
			$Satsuki::Base::RELOAD = 1;	# if Base.pm compile error, force reload
			require Satsuki::Base;
			$Satsuki::Base::RELOAD = 0;
		}

		#--------------------------------------------------
		# Timer start
		#--------------------------------------------------
		if ($ENV{SatsukiTimer}) { require Satsuki::Timer; }
		my $timer;
		if (defined $Satsuki::Timer::VERSION) {
			$timer = Satsuki::Timer->new();
			$timer->start();
		}

		#--------------------------------------------------
		# Initalize
		#--------------------------------------------------
		$ROBJ = Satsuki::Base->new();	# root object
		$ROBJ->{Timer} = $timer;
		$ROBJ->{AutoReload} = $flag;

		$ROBJ->init_for_httpd();

		if ($FS_CODE) {
			# file system's locale setting
			$ROBJ->set_fslocale($FS_CODE);
		}

		#--------------------------------------------------
		# main
		#--------------------------------------------------
		$ROBJ->start_up();
		$ROBJ->finish();
	};
	$@ && print STDERR "$@\n";

	# ライブラリのセーブ
	&Satsuki::AutoReload::save_lib();

	$state->{status} = $ROBJ->{Status};
	$state->{send}   = $ROBJ->{Send} || 0;
}

###############################################################################
# Response
###############################################################################
sub _200_ok {
	my $state = shift;
	$state->{status}     = 200;
	$state->{status_msg} = '200 OK';
	&send_response($state, @_);
}
sub _304_not_modified {
	my $state = shift;
	$state->{status}     = 304;
	$state->{status_msg} = '304 Not Modified';
	&send_response($state, @_);
}
sub _400_bad_request {
	my $state = shift;
	$state->{status}     = 400;
	$state->{status_msg} = '400 Bad Request';
	&send_response($state, @_);
}
sub _403_forbidden {
	my $state = shift;
	$state->{status}     = 403;
	$state->{status_msg} = '400 Forbidden';
	&send_response($state, @_);
}
sub _500_internal_server_error {
	my $state = shift;
	my $data  = shift;
	$state->{status}     = 500;
	$state->{status_msg} = '500 Internal Server Error';
	&send_response($state, '', $data);
}
sub send_response {
	my $state  = shift || {};
	my $status = $state->{status};
	my $header = shift || '';
	my $data   = shift || $state->{status_msg} . "\n";
	my $c_len  = length($data);
	my $sock   = $state->{sock};
	my $date   = &rfc_date( time() );

	if (index($header, 'Content-Length:')<0) {
		$header .= "Content-Length: $c_len\r\n";
	}
	if (index($header, 'Content-Type:')<0) {
		$header .= "Content-Type: text/plain\r\n";
	}
	my $header = <<HEADER;
HTTP/1.0 $state->{status_msg}\r
Date: $date\r
Server: $ENV{SERVER_SOFTWARE}\r
Connection: close\r
$header\r
HEADER
	print $sock $header;

	$state->{send} = 0;
	if ($state->{method} ne 'HEAD' && $status !~ /^304 /) {
		print $sock $data;
		$state->{send} = length($header) + $c_len;
	}
}

###############################################################################
# sub routine
###############################################################################
sub set_bit	{ vec($_[0], fileno($_[1]), 1) = 1; }
sub reset_bit	{ vec($_[0], fileno($_[1]), 1) = 0; }
sub check_bit   { vec($_[0], fileno($_[1]), 1); }
sub rfc_date {
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(shift);

	my($wd, $mn);
	$wd = substr('SunMonTueWedThuFriSat',$wday*3,3);
	$mn = substr('JanFebMarAprMayJunJulAugSepOctNovDec',$mon*3,3);

	return sprintf("$wd, %02d $mn %04d %02d:%02d:%02d GMT"
		, $mday, $year+1900, $hour, $min, $sec);
}

#------------------------------------------------------------------------------
# deny directories
#------------------------------------------------------------------------------
sub search_dir_file {
	my $file = shift || '.htaccess';
	opendir(my $fh, './') || return [];

	my @ary;
	foreach(readdir($fh)) {
		if ($_ eq '.' || $_ eq '..' )  { next; }
		if (!-d $_) { next; }
		if (-e "$_/$file") {
			push(@ary, $_);
		}
	}
	closedir($fh);
	return @ary;
}

#------------------------------------------------------------------------------
# no buffered read <$sock>
#------------------------------------------------------------------------------
sub read_sock_1line {
	my $sock = shift;
	my $line = '';
	my $c;
	while($c ne "\n") {
		if (sysread($sock, $c, 1) != 1) { return; }
		$line .= $c;
	}
	return $line;
}

#------------------------------------------------------------------------------
# deny directories
#------------------------------------------------------------------------------
sub generate_random_string {
	my $_SALT = 'xL6R.JAX38tUanpyFfjZGQ49YceKqs2NOiwB/ubhHEMzo7kSC5VDPWrm1vgT0lId';
	my $len = int(shift) || 32;
	my $str = '';
	my ($sec, $msec) = Time::HiRes::gettimeofday();
	foreach(1..$len) {
		$str .= substr($_SALT, (int(rand(0x1000000) * $msec)>>8) & 0x3f, 1);
	}
	return $str;
}
