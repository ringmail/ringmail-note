package Note::SQL::Table;
use strict;
use warnings;

use vars qw($SQLGEN);

use Moose;
use Moose::Exporter;
use Iterator;

use Note::Param;
use Note::Iterator;
use Note::SQL::Abstract;
use Note::SQL::Database;

Moose::Exporter->setup_import_methods(
	'as_is' => ['sqltable'],
);

has 'database' => (
	'is' => 'rw',
	'isa' => 'Note::SQL::Database',
	'required' => 1,
);

has 'handle' => (
	'is' => 'rw',
	'isa' => 'Ref',
	'lazy' => 1,
	'default' => sub {
		my ($obj) = @_;
		return $obj->database()->handle(),
	},
);

has 'table' => (
	'is' => 'rw',
	'isa' => 'Str',
);

our $SQLGEN = new Note::SQL::Abstract();

sub sqltable
{
	my $table = shift;
	my $db = shift;
	my %param = (
		'table' => $table,
	);
	if (defined $db)
	{
		$param{'database'} = $db;
	}
	return __PACKAGE__->new(\%param);
}

sub do
{
	my ($obj, $param) = get_param(@_);
	my $bind = [];
	if (defined $param->{'bind'})
	{
		$bind = $param->{'bind'};
	}
	my $sql;
	if (defined $param->{'query'})
	{
		$sql = $param->{'query'};
		my $sth = $obj->query(
			'sql' => $sql,
			'bind' => $bind,
		);
		return $obj->fetch({
			'sth' => $sth,
			%$param,
		});
	}
	elsif (defined $param->{'sql'})
	{
		$sql = $param->{'sql'};
		my $sth = $obj->query(
			'sql' => $sql,
			'bind' => $bind,
		);
	}
	else
	{
		die('Invalid parameters');
	}
}

sub select_param
{
	my ($obj, $param) = get_param(@_);
	my $sel = {};
	if (defined $param->{'select'})
	{
		$sel->{'fields'} = $param->{'select'};
	}
	else
	{
		$sel->{'fields'} = '*';
	}
	if (defined $param->{'from'}) # alternate for 'table'
	{
		$param->{'table'} = $param->{'from'};
	}
	if (defined $param->{'table'})
	{
		if (ref($param->{'table'}) and $param->{'table'} =~ /ARRAY/)
		{
			$sel->{'table'} = join(',', @{$param->{'table'}});
		}
		else
		{
			$sel->{'table'} = $param->{'table'};
		}
	}
	else
	{
		$sel->{'table'} = $obj->table();
	}
	foreach my $k (qw/where order group join join_left/)
	{
		if (defined $param->{$k})
		{
			$sel->{$k} = $param->{$k};
		}
	}
	return $sel;
}

sub fetch
{
	my ($obj, $param) = get_param(@_);
	my $sth = $param->{'sth'};
	my $res = undef;
	if ($param->{'iterator'})
	{
		return new Note::Iterator(
			'iterator' => new Iterator(sub {
				my $res = undef;
				if ($param->{'array'})
				{
					$res = $sth->fetchrow_arrayref();
					if ($param->{'result'})
					{
						$res = $res->[0];
					}
				}
				else
				{
					$res = $sth->fetchrow_hashref();
				}
				unless (defined $res)
				{
					if ($sth->err())
					{
						my $err = $sth->err();
						die(qq|Iterator fetch error: $err|);
					}
					$sth->finish();
					Iterator::is_done();
				}
				return $res;
			}),
		);
	}
	elsif ($param->{'array'})
	{
		if ($param->{'result'})
		{
			$res = $sth->fetchrow_arrayref();
			$res = $res->[0];
		}
		else
		{
			$res = $sth->fetchall_arrayref();
		}
	}
	else
	{
		if ($param->{'result'})
		{
			$res = $sth->fetchrow_hashref();
		}
		else
		{
			my @result = ();
			while (my $r = $sth->fetchrow_hashref())
			{
				push @result, $r;
			}
			$res = \@result;
		}
	}
	return $res;
}

sub get
{
	my ($obj, $param) = get_param(@_);
	my $sel = $obj->select_param($param);
	my ($sql, $bind) = $SQLGEN->select($sel);
	my $sth = $obj->query(
		'sql' => $sql,
		'bind' => $bind,
	);
	return $obj->fetch({
		'sth' => $sth,
		%$param,
	});
}

sub count
{
	my ($obj, $whr) = get_param(@_);
	return $obj->get(
		'array' => 1,
		'result' => 1,
		'select' => ['count(id)'],
		'where' => $whr,
	);
}

sub query
{
	my ($obj, $param) = get_param(@_);
	my $sql = $param->{'sql'};
	my $bind = $param->{'bind'};
	my $dbh = $obj->handle();
	my $sth = $param->{'sth'};
	my $rv = 0;
	#print "SQL: $sql -- (". join(', ', @$bind). ")\n";
	eval {
		if ($dbh->isa('DBIx::Connector'))
		{
			$dbh->run(
				'fixup' => sub {
					unless (defined $sth)
					{
						$sth = $_->prepare($sql);
					}
					unless ($param->{'prepare'})
					{
						$rv = $sth->execute(@$bind);
					}
					return $sth;
				},
			);
		}
		else
		{
			unless (defined $sth)
			{
				$sth = $dbh->prepare($sql);
			}
			unless ($param->{'prepare'})
			{
				$rv = $sth->execute(@$bind);
			}
		}
	};
	if ($@)
	{
		if ($@ =~ /^DBD::mysql::st execute failed: MySQL server has gone away/)
		{
			if ($param->{'retry'} < 3)
			{
				$param->{'retry'}++;
				return $obj->query($param);
			}
		}
		else
		{
			die("SQL Error For Query:\n$sql\n$@");
		}
	}
	return $sth;
}

sub add
{
	my ($obj, $param) = get_param(@_);
	return $obj->set(
		'insert' => $param,
	);
}

sub set
{
	my ($obj, $param) = get_param(@_);
	my $ins = {
		'table' => $param->{'table'},
	};
	$ins->{'table'} //= $obj->table();
	my ($sql, $bind);
	if (defined $param->{'insert'})
	{
		$ins->{'fields'} = $param->{'insert'};
		($sql, $bind) = $SQLGEN->insert($ins);
	}
	elsif (defined $param->{'update'})
	{
		$ins->{'fields'} = $param->{'update'};
		if (defined $param->{'where'})
		{
			$ins->{'where'} = $param->{'where'};
		}
		($sql, $bind) = $SQLGEN->update($ins);
	}
	elsif (defined $param->{'replace'})
	{
		$ins->{'fields'} = $param->{'replace'};
		($sql, $bind) = $SQLGEN->replace($ins);
	}
	if (defined $sql)
	{
		my $sth = $obj->query(
			'sql' => $sql,
			'bind' => $bind,
		);
		return $sth->rows();
	}
	else
	{
		die('Invalid parameters');
	}
}

sub delete
{
	my ($obj, $param) = get_param(@_);
	my $del = {
		'table' => $param->{'table'},
	};
	$del->{'table'} //= $obj->table();
	if (defined $param->{'where'})
	{
		$del->{'where'} = $param->{'where'};
	}
	my ($sql, $bind) = $SQLGEN->delete($del);
	my $sth = $obj->query(
		'sql' => $sql,
		'bind' => $bind,
	);
	return $sth->rows();
}

sub last_insert_id
{
	my ($obj) = @_;
	my $sth = $obj->query(
		'sql' => 'select last_insert_id()',
	);
	return $obj->fetch({
		'sth' => $sth,
		'array' => 1,
		'result' => 1,
	});
}

if ($::config{'production'})
{
	__PACKAGE__->meta()->make_immutable();
}

1;

