package Note::Session;
use strict;
use warnings;
no warnings 'uninitialized';

use Moose;
use Storable 'nfreeze', 'thaw';
use POSIX 'strftime';
use String::Random;
use Data::Dumper;
use CGI::Cookie;

use Note::Param;
use Note::Page;
use Note::SQL::Database;
use Note::SQL::Sequence;

has 'page' => (
	'is' => 'rw',
	'isa' => 'Note::Page',
	'required' => 1,
);

has 'type' => (
	'is' => 'rw',
	'isa' => 'Str',
	'required' => 1,
);

# for type 'file'
has 'path' => (
	'is' => 'rw',
	'isa' => 'Maybe[Str]',
);

# for type 'sql'
has 'database' => (
	'is' => 'rw',
	'isa' => 'Maybe[Note::SQL::Database]',
);

has 'cookie_key' => (
	'is' => 'rw',
	'isa' => 'Str',
	'default' => sub { return 'nskey'; },
);

has 'sequence' => (
	'is' => 'rw',
	'isa' => 'Note::SQL::Sequence',
	'lazy' => 1,
	'default' => sub {
		my ($obj) = @_;
		return new Note::SQL::Sequence(
			'database' => $obj->database(),
		);
	},
);

has 'id' => (
	'is' => 'rw',
	'isa' => 'Str',
	'lazy' => 1,
	'default' => sub {
		my ($obj) = @_;
		my $page = $obj->page();
		my $type = $obj->type();
		my $cookies = $page->request()->cookies();
		#::log("Cookies", $cookies);
		#my $skey = $cookies->{$obj->cookie_key()};
		my @cklist = ();
		my $ckey = $obj->cookie_key();
		$ckey = quotemeta($ckey);
		foreach my $ck (keys %$cookies)
		{
			if ($ck =~ /^$ckey-(\d{1,11})$/)
			{
				my $ts = $1;
				if ($cookies->{$ck} =~ /^[A-Za-z0-9]{32}$/)
				{
					push @cklist, [$ts, $cookies->{$ck}];
				}
			}
		}
		if (scalar @cklist)
		{
			my @cksort = sort { $a->[0] <=> $b->[0] } @cklist;
			my $skey = $cksort[-1]->[1];
			#::log("Skey", $skey);
			#::log("Stype: $type ". $obj->path());
			if ($type eq 'sql')
			{
				my $sid = $obj->database()->table('note_session')->get(
					'array' => 1,
					'select' => ['id', 'data'],
					'where' => {
						'skey' => $skey,
					},
				);
				if (scalar @$sid)
				{
					$obj->{'cache'} = thaw($sid->[0]->[1]);
					return $sid->[0]->[0];
				}
			}
			elsif ($type eq 'file')
			{
				if (-e ($obj->path(). '/'. $skey. '.sto'))
				{
					return $skey;
				}
			}
		}
		return $obj->create();
	},
);
	
sub random_key
{   
	my ($obj, $tbl) = @_;
	my $sr = new String::Random();
	my $rk;
	my $type = $obj->type();
	if ($type eq 'sql')
	{
		do {
			$rk = $sr->randregex('[A-Za-z0-9]{32}');
		} while ($tbl->count(
			'skey' => $rk,
		));
	}
	elsif ($type eq 'file')
	{
		do {
			$rk = $sr->randregex('[A-Za-z0-9]{32}');
		} while (-e ($obj->path(). '/'. $rk. '.sto'));
	}
	return $rk;
}

sub create
{
	my ($obj) = @_;
	my $page = $obj->page();
	my $type = $obj->type();
	my $ipaddr = $page->env()->{'REMOTE_ADDR'};
	my $expires = time() + (30 * 24 * 60 * 60);
	my $secure = ($page->request()->secure()) ? 1 : 0;
	my $skey;
	my $id;
	if ($type eq 'sql')
	{
		my $db = $obj->database();
		#$id = $obj->sequence()->nextid();
		my $tbl = $db->table('note_session');
		$skey = $obj->random_key($tbl);
		$tbl->set(
			'insert' => {
				#'id' => $id,
				'skey' => $skey,
				'ipv4_addr' => $ipaddr,
				'ts_expires' => strftime("%F %T", localtime($expires)),
				'ts_created' => strftime("%F %T", localtime()),
				'secure' => $secure,
				'data' => nfreeze({}),
			},
		);
		$id = $tbl->last_insert_id();
	}
	elsif ($type eq 'file')
	{
		$skey = $obj->random_key();
		my $fpath = $obj->path(). '/'. $skey. '.sto';
		unless (open(F, '>', $fpath))
		{
			die(qq|Open '$fpath' Failed: $!|);
		}
		print F nfreeze({});
		close(F);
		#::log("SCreate: $fpath");
		$id = $skey;
	}
	my $host = $page->env()->{'HTTP_HOST'};
	$host =~ s/\:.*//;
	$page->response()->cookies()->{$obj->cookie_key(). '-'. time()} = {
		'value' => $skey,
		'path' => '/',
		'domain' => $host,
		'expires' => $expires,
		(($secure) ? ('secure' => $secure) : ()),
	};
	#::_log("Out cookie:", $page->response()->cookies());
	return $id;
}

sub get
{
	my ($obj, $k) = @_;
	my $page = $obj->page();
	my $type = $obj->type();
	if ($type eq 'sql')
	{
		if (defined $obj->{'cache'})
		{
			return $obj->{'cache'};
		}
		my $db = $obj->database();
		my $v = $db->table('note_session')->get(
			'array' => 1,
			'result' => 1,
			'select' => ['data'],
			'where' => {
				'id' => $obj->id(),
			},
		);
		return undef unless (defined $v);
		return thaw($v);
	}
	elsif ($type eq 'file')
	{
		my $id = $obj->id();
		my $fpath = $obj->path(). '/'. $id. '.sto';
		unless (-e $fpath)
		{
			return undef;
		}
		unless (open (F, '<', $fpath))
		{
			die(qq|Open '$fpath' Failed: $!|);
		}
		local $/;
		$/ = undef;
		my $data = <F>;
		close(F);
		return thaw($data);
	}
}

sub set
{
	my ($obj, $v) = @_;
	my $page = $obj->page();
	my $type = $obj->type();
	my $id = $obj->id();
	if ($type eq 'sql')
	{
		my $tbl = $obj->database()->table('note_session');
		$tbl->set(
			'update' => {
				'data' => nfreeze($v),
			},
			'where' => {
				'id' => $id,
			},
		);
		$obj->{'cache'} = $v;
	}
	elsif ($type eq 'file')
	{
		my $id = $obj->id();
		my $fpath = $obj->path(). '/'. $id. '.sto';
		unless (-e $fpath)
		{
			return undef;
		}
		unless (open (F, '>', $fpath))
		{
			die(qq|Open '$fpath' Failed: $!|);
		}
		print F nfreeze($v);
		close(F);
	}
	return $v;
}

1;

