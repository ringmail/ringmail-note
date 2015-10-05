package Note::PSGI;
use strict;
use warnings;

use vars qw();

use Moose;
use Plack::Request;
use Plack::Response;
use Data::Dumper;
use Config::General;
use Scalar::Util 'reftype';
use DBIx::Connector;
use Carp::Always;
use JSON::XS;
use POSIX 'strftime';
use Time::HiRes 'gettimeofday', 'tv_interval';
use Module::Load;
use Module::Refresh;

$Note::Config::Load = 0;
use Note::Config;

use Note::Param;
use Note::App;
use Note::Page;
use Note::Template;
use Note::File::JSON;
use Note::Row;
use Note::SQL::Table 'sqltable';
use Note::SQL::Database;
use Note::Log;

no warnings qw(uninitialized);

has 'config' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'lazy' => 1,
	'default' => sub { return {}; },
);

has 'config_apps' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'default' => sub { return {}; },
);

has 'database' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'lazy' => 1,
	'default' => sub { return {}; },
);

has 'root' => (
	'is' => 'rw',
	'isa' => 'Str',
);

# hostname and port of the current request
has 'hostname' => (
	'is' => 'rw',
	'isa' => 'Str',
);

has 'port' => (
	'is' => 'rw',
	'isa' => 'Int',
	'default' => sub { return 80; },
);

has 'page' => (
	'is' => 'rw',
	'isa' => 'Note::Page',
);

has 'app_name' => (
	'is' => 'rw',
	'isa' => 'Str',
);

has 'app' => (
	'is' => 'rw',
	'isa' => 'Note::App',
);

has 'app_map' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'default' => sub { return {}; },
);

has 'app_class' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'default' => sub { return {}; },
);

has 'storage' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'default' => sub { return {}; },
);

sub setup
{
	my ($obj, $param) = get_param(@_);
	Module::Refresh->new();
	my $cfg = new Note::Config($param);
	$cfg->setup();
	$obj->root($cfg->root());
	$obj->config($cfg->config());
	$obj->config_apps($cfg->config_apps());
	$obj->storage($cfg->storage());
	$obj->app_map($cfg->app_map());
	$obj->app_class($cfg->app_class());
	$main::note_config = $cfg;
}

sub translate_hostname
{
	my $obj = shift;
	my $hostname = shift;
	if ($hostname =~ s/\:(.*)//)
	{
		$obj->port($1); # not the default port
	}
	if ($hostname =~ s/^www\.//)
	{
		$obj->hostname('www.'. $hostname); # take the user to the same site (w/ www.)
	}
	else
	{
		$obj->hostname($hostname); # no www. or removed by upstream server
	}
	return $hostname;
}

sub translate_path
{
	my ($obj, $param) = get_param(@_);
	my $hostname = $param->{'hostname'};
	my $path = $param->{'path'};
	#::_log("Path: $path");
	$path ||= '';
	$path =~ s{\?.*}{};
	$path =~ s{^/}{};
	$path =~ s{/$}{};
	my @p = split (/\//, $path);
	return \@p;
}

sub build_page
{
	#die("test");
	my ($obj, $param) = get_param(@_);
	my $start = [gettimeofday()];
	$Note::Log::start = [gettimeofday()];
	$Note::Log::timer = [gettimeofday()];
	$param->{'response'}->status(200); # start with OK
	#::_log($param);
	# dispatch page lookup
	my $app = $obj->app();
	$param->{'app'} = $app;
	my $page = $app->dispatch($param);
	unless (defined $page)
	{
		$param->{'response'}->status(404);
		$param->{'response'}->content_type('text/plain');
		$param->{'response'}->body('Not found');
		return;
	}
	unless ($page->isa('Note::Page'))
	{
		die('Not an instance of Note::Page or its subclass.');
	}
	if ($page->init($param))
	{
		$page->run_command();
		${$param->{'body'}} = $page->load($param);
	}
	my $tm = tv_interval($start);	
	my $ip = $param->{'request'}->address();
	::_log(strftime("%F %T", localtime()). ' /'. join('/', @{$param->{'path'}}). " Time: $tm ($$) [$ip]");
}

sub run_psgi
{
	my $obj = shift;
	my $env = shift;
	Module::Refresh->refresh();
	#print STDERR Dumper($env);
	my $req = new Plack::Request($env);
	my $form = { $req->parameters()->flatten() };
	my $ip = $env->{'REMOTE_ADDR'};
	my $ua = $env->{'HTTP_USER_AGENT'};
	my $hostname = $env->{'HTTP_HOST'};
	$hostname = $obj->translate_hostname($hostname);
	my $appname = undef;
	my $res = new Plack::Response();
	if (exists $obj->app_map()->{'hostname'}->{$hostname})
	{
		$appname = $obj->app_map()->{'hostname'}->{$hostname};
	}
	unless (defined $appname)
	{
		$appname = $obj->app_map()->{'default'};
	}
	if (defined $appname)
	{
		$obj->app_name($appname);
		my $appcls = $obj->app_class();
		if (exists $appcls->{$appname})
		{
			$obj->app($appcls->{$appname});
		}
		else
		{
			$obj->app(new Note::App(
				'name' => $appname,
				'config' => $obj->config_apps()->{$appname} || {},
				'root' => $obj->root(). '/app/'. $appname,
				'storage' => $obj->storage(),
			));
		}
	}
	if (defined $appname)
	{
		my $appcfg = $obj->app()->config();
		# set default SQL database for application
		my $db = $appcfg->{'sql_database'};
		$main::app_config = $appcfg;
		if (defined $db)
		{
			$Note::Row::Database = $obj->storage()->{$db};
		}
		my $path = $obj->translate_path(
			'hostname' => $hostname,
			'path' => $env->{'REQUEST_URI'},
		);
		#$res->content_type('text/html');
		my $tpl = new Note::Template(
			'root' => $obj->root(). '/app/'. $obj->app_name(). '/template',
		);
		my $body = '';
		my %data = (
			'root' => $obj->root(). '/app/'. $obj->app_name(),
			'remote_ip' => $ip,
			'hostname' => $obj->hostname(),
			'port' => $obj->port(),
			'request' => $req,
			'response' => $res,
			'template' => $tpl,
			'path' => $path,
			'form' => $form,
			'env' => $env,
			'body' => \$body,
		);
		my $warning = undef;
		eval {
			local $SIG{__WARN__};
			$SIG{__WARN__} = sub {
				$warning = $_[0];
				return;
			};
			$obj->build_page(\%data);
		};
		if (
			defined($res->headers()->{'location'}) ||
			$res->status() == 404
		) {
			return $res->finalize();
		}
		if (defined $warning)
		{
			::_errorlog("Warning", $warning);
		}
		if ($@) # handle error
		{
			::_errorlog("Build Page Error", $@);
			$res->content_type('text/plain');
			$res->status(500);
			$res->body($@);
			$res->content_length(length($@));
		}
		else
		{
			$res->body($body);
			$res->content_length(length($body));
		}
	}
	else
	{
		::_errorlog(qq|Unknown application: '$appname' for hostname: '$hostname'|, $@);
		$res->status(500);
		$res->body("Unknown application for domain name");
		$res->content_type('text/plain');
		$res->content_length(length($@));
	}
	#::_log("Response", $res);
	return $res->finalize();
}

1;

