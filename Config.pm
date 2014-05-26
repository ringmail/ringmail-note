package Note::Config;
use strict;
use warnings;

use vars qw($File $Data);

use Moose;
use Data::Dumper;
use Config::General;
use Scalar::Util 'reftype';
use DBIx::Connector;
use JSON::XS;
use POSIX 'strftime';
use Time::HiRes 'gettimeofday', 'tv_interval';
use Module::Load;

use Note::Param;
use Note::File::JSON;
use Note::SQL::Database;

no warnings qw(uninitialized);

has 'config_file' => (
	'is' => 'rw',
	'isa' => 'Str',
);

has 'root' => (
	'is' => 'rw',
	'isa' => 'Str',
);

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
	my ($obj) = @_;
	# read configuration
	if (defined $obj->config_file())
	{
		my $cg = new Config::General(
			'-ConfigFile' => $obj->config_file(),
		);
		my %cfg = $cg->getall();
		foreach my $k (keys %cfg)
		{
			if (reftype($cfg{$k}) eq 'HASH')
			{
				$cfg{$k} = [$cfg{$k}];
			}
		}
		$obj->config(\%cfg);
	}
	my $cfgrc = $obj->config();
	$obj->root($cfgrc->{'root'});
	# connect to databases
	if (exists $cfgrc->{'storage'})
	{
		my $mpf = new Note::File::JSON(
			'file' => $obj->root(). '/'. $cfgrc->{'storage'},
		);
		my $ds = $mpf->read_file();
		foreach my $k (sort keys %$ds)
		{
			my $dsrec = $ds->{$k};
			my $stores = $obj->storage();
			if ($dsrec->{'type'} eq 'dbi')
			{
				# DBI SQL Database: MySQL, SQLite, etc...
				my $name = $k;
				$stores->{$name} = new Note::SQL::Database($dsrec);
			}
			else
			{
				die(qq|Unknown data store type: '$dsrec->{'type'}'|);
			}
		}
	}
	# read application map
	if (exists $cfgrc->{'apps_map'})
	{
		my $mpf = new Note::File::JSON(
			'file' => $obj->root(). '/'. $cfgrc->{'apps_map'},
		);
		my $appmap = $mpf->read_file();
		$obj->app_map($appmap);
	}
	my $approot = $obj->root(). '/cfg/app';
	if (-d $approot)
	{
		my @files = glob("$approot/*.njs");
		my $appconfig = $obj->config_apps();
		my $storage = $obj->storage();
		foreach my $fn (@files)
		{
			my $appname = '';
			if ($fn =~ /\/(\w+)\.njs$/)
			{
				$appname = $1;
				my $cfga = new Note::File::JSON(
					'file' => $fn,
				);
				my $appcfg = $cfga->read_file();
				#::_log("App Config($appname):", $appcfg);
				$appconfig->{$appname} = $appcfg;
				my $appcls = $obj->app_class();
				if (exists $appcfg->{'class'})
				{
					my $appclass = $appcfg->{'class'};
					load($appclass);
					# create instance
					my $app = $appclass->new(
						'name' => $appname,
						'config' => $appcfg,
						'root' => $obj->root(). '/app/'. $appname,
						'storage' => $storage,
					);
					unless (blessed($app) && $app->isa('Note::App'))
					{
						die(qq|Invalid application class: '$appclass'|);
					}
					$appcls->{$appname} = $app;
				}
				else
				{
					$appcls->{$appname} = new Note::App(
						'name' => $appname,
						'config' => $appcfg,
						'root' => $obj->root(). '/app/'. $appname,
						'storage' => $storage,
					);
				}
			}
			else
			{
				die(qq|Invalid application config file: '$fn'|);
			}
		}
	}
}

END: {
	if (length $Note::Config::File)
	{
		$main::note_config = new Note::Config(
			'config_file' => $Note::Config::File,
		);
		$main::note_config->setup();
		#print "Loaded Config\n";
	}
}

1;
