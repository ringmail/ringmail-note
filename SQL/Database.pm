package Note::SQL::Database;
use strict;
use warnings;

use vars qw();

use Moose;
use DBI;
use DBIx::Connector;
use SQL::Translator;
use SQL::Translator::Parser::MySQL;
use SQL::Translator::Parser::SQLite;
use Data::Dumper;

use Note::Param;
use Note::SQL::Table;

has 'handle' => (
	'is' => 'rw',
	'isa' => 'Ref',
	'required' => 1,
);

has 'driver' => (
	'is' => 'ro',
	'isa' => 'Any',
	'lazy' => 1,
	'default' => sub {
		my $obj = shift;
		return $obj->dbi()->{'Driver'}->{'Name'};
	},
);

has 'username' => (
	'is' => 'ro',
	'isa' => 'Any',
	'lazy' => 1,
	'default' => sub {
		my $obj = shift;
		return $obj->dbi()->{'Username'};
	},
);

has 'name' => (
	'is' => 'ro',
	'isa' => 'Any',
	'lazy' => 1,
	'default' => sub {
		my $obj = shift;
		return $obj->dbi()->{'Name'};
	},
);

sub BUILDARGS
{
	my ($class, $param) = get_param(@_);
	my %rec = ();
	if ($param->{'type'} eq 'sqlite')
	{
		if (defined $param->{'file'})
		{
			my $file = $param->{'file'};
			$param->{'dsn'} = "dbi:SQLite:$file";
		}
	}
	if (defined $param->{'dsn'})
	{
		my $dsn = $param->{'dsn'};
		my $user = $param->{'login'} || '';
		my $pass = $param->{'password'} || '';
		$rec{'handle'} = new DBIx::Connector($dsn, $user, $pass, {
			'PrintError' => 0,
			'RaiseError' => 1,
			'AutoCommit' => 1,
			#'TraceLevel' => '1|SQL',
		});
	}
	return \%rec;
}

sub do
{
	my ($obj, $sql) = @_;
	my $dbh = $obj->handle();
	if ($dbh->isa('DBIx::Connector'))
	{
		return $dbh->run(
			'fixup' => sub {
				$_->do($sql);
			},
		);
	}
	else
	{
		return $dbh->do($sql);
	}
}

sub query
{
	my ($obj, $sql, @bind) = @_;
	my $dbh = $obj->handle();
	my $sth;
	if ($dbh->isa('DBIx::Connector'))
	{
		$dbh->run(
			'fixup' => sub {
				$sth = $_->prepare($sql);
				my $rv = $sth->execute(@bind);
			},
		);
	}
	else
	{
		$sth = $dbh->prepare($sql);
		my $rv = $sth->execute(@bind);
	}
	my $res = $sth->fetchall_arrayref();
	return $res;
}

sub txn
{
	my $obj = shift;
	my $subr = shift;
	my $h = $obj->handle();
	unless ($h->isa('DBIx::Connector'))
	{
		die('Transactions only supported with DBIx::Connector');
	}
	unless (ref($subr) eq 'CODE')
	{
		die('Transactions requires a subroutine reference');
	}
	return $h->txn('fixup' => $subr);
}

sub dbi
{
	my $obj = shift;
	my $h = $obj->handle();
	if ($h->isa('DBIx::Connector'))
	{
		return $h->dbh();
	}
	elsif ($h->isa('DBI::db'))
	{
		return $h;
	}
	else
	{
		die('Invalid database handle');
	}
}

sub get_sources
{
	my ($obj, $param) = get_param(@_);
	my $drv = $obj->driver();
	return [DBI->data_sources($drv)];
}

sub get_databases
{
	my ($obj, $param) = get_param(@_);
	my $drv = $obj->driver();
	if ($drv eq 'mysql')
	{
		my $dbh = $obj->dbi();
		return [$dbh->func('_ListDBs')];
	}
	elsif ($drv eq 'SQLite')
	{
		my $dbh = $obj->dbi();
		my $sth = $dbh->table_info();
		my $res = $sth->fetchall_arrayref();
		my %seen = ();
		my @dbs = grep {! $seen{$_}++} map {$_->[1]} @$res;
		return \@dbs;
	}
	else
	{
		die(qq|Unsupported database: '$drv'|);
	}
}

sub get_tables
{
	my ($obj, $param) = get_param(@_);
	my $drv = $obj->driver();
	my $dbn = '';
	if (defined $param->{'database'})
	{
		$dbn = $param->{'database'};
	}
	if ($drv eq 'mysql')
	{
		if (length($dbn))
		{
			$dbn = " from `$dbn`";
		}
		my $q = $obj->query('show tables'. $dbn);
		@$q = map {$_->[0]} @$q;
		return $q;
	}
	elsif ($drv eq 'SQLite')
	{
		my $dbh = $obj->dbi();
		my $sth = $dbh->table_info(undef, $dbn);
		my $res = $sth->fetchall_arrayref();
		my @tables = map {$_->[2]} @$res;
		return \@tables;
	}
	else
	{
		die('Unsupported database');
	}
}

sub has_table
{
	my ($obj, $dbname, $table) = @_;
	my $drv = $obj->driver();
	if ($drv eq 'SQLite')
	{
		my $dbh = $obj->dbi();
		my $sth = $dbh->table_info(undef, $dbname, $table);
		my $res = $sth->fetchall_arrayref();
		if (scalar @$res)
		{
			if (lc($res->[0]->[2]) eq lc($table))
			{
				return 1;
			}
		}
		return 0;
	}
	else
	{
		die(qq|Unsupported database: '$drv'|);
	}	
}

sub create_table
{
	my ($obj, $param) = get_param(@_);
	my $schema = $param->{'schema'};
	my $dbname = $param->{'database'} || $schema->name();
	my $table = $param->{'table'};
	unless (defined $table)
	{
		my @ts = $schema->get_tables();
		$table = $ts[0];
	}
	my $drv = $obj->driver();
	if ($obj->has_table($dbname, $table))
	{
		# already has the table, do something
		if ($param->{'drop'})
		{
			# drop the table
			if ($drv eq 'SQLite')
			{
				$obj->do("DROP TABLE $dbname.$table");
			}
			else
			{
				die(qq|Unsupported database: '$drv'|);
			}	
		}
		elsif ($param->{'truncate'})
		{
			if ($drv eq 'SQLite')
			{
				$obj->do("DELETE FROM $dbname.$table");
				return;
			}
			else
			{
				die(qq|Unsupported database: '$drv'|);
			}	
		}
		elsif (exists $param->{'alter'})
		{
			$obj->do($param->{'alter'});
			return;
		}
		elsif (! $param->{'ignore'})
		{
			# table already exists
			die(qq|Table: '$table' already exists in database: '$dbname'|);
		}
	}
	if ($drv eq 'SQLite')
	{
		my $sql = $obj->format_schema(
			'schema' => $schema,
			'format' => 'SQLite',
		);
		my $sth = $obj->do($sql);
		return $sth;
	}
	else
	{
		die(qq|Unsupported database: '$drv'|);
	}	
}

sub get_create_table
{
	my ($obj, $param) = get_param(@_);
	my $tbl = $param->{'table'};
	my $drv = $obj->driver();
	if ($drv eq 'mysql')
	{
		$tbl = "`$tbl`";
		my $q = $obj->query('show create table '. $tbl);
		return $q->[0]->[1];
	}
	elsif ($drv eq 'SQLite')
	{
		my $q = $obj->table('sqlite_master')->get(
			'array' => 1,
			'result' => 1,
			'select' => 'sql',
			'where' => {
				'name' => $tbl,
			},
		);
		return $q;
	}
	else
	{
		die(qq|Unsupported database: '$drv'|);
	}
}

sub parse_create_table
{
	my ($obj, $param) = get_param(@_);
	my $sql;
	if (defined $param->{'sql'})
	{
		$sql = $param->{'sql'};
	}
	else
	{
		$sql = $obj->get_create_table($param);
		$sql .= ';';
	}
	print Dumper($sql);
	my $tr = new SQL::Translator;
	my $drv = $obj->driver();
	if ($drv eq 'mysql')
	{
		$tr->parser(sub {
			my ($trs, $data) = @_;
			SQL::Translator::Parser::MySQL::parse($trs, $sql);
			return 1;
		});
		my $out = $tr->translate();
		return $out;
	}
	elsif ($drv eq 'SQLite')
	{
		$tr->parser(sub {
			my ($trs, $data) = @_;
			SQL::Translator::Parser::SQLite::parse($trs, $sql);
			return 1;
		});
		my $out = $tr->translate();
		return $out;
	}
	else
	{
		die(qq|Unsupported database: '$drv'|);
	}
}

sub format_schema
{
	my ($obj, $param) = get_param(@_);
	my $sch = $param->{'schema'};
	my $format = $param->{'format'};
	my %prm = ();
	if ($format =~ /^sqlite$/i)
	{
		$prm{'producer_args'} = {
			'no_transaction' => 1,
		};
	}
	my $tr = new SQL::Translator(
		'producer' => $format,
		'no_comments' => 1,
		%prm,
	);
	$tr->parser(sub{
		my ($trs) = @_;
		$trs->{'schema'} = $sch;
		$sch->{'translator'} = $trs;
	});
	my $out = $tr->translate();
	return $out;
}

sub table
{
	my ($obj, $tablename) = @_;
	return new Note::SQL::Table(
		'database' => $obj,
		'handle' => $obj->handle(),
		'table' => $tablename,
	);
}

# static method
sub default_database
{
	if (defined $Note::Row::Database)
	{
		return $Note::Row::Database;
	}
	else
	{
		my $dbkey = $main::note_config->{'config'}->{'default_sql_database'};
		return $main::note_config->{'storage'}->{$dbkey};
	}
}

1;
