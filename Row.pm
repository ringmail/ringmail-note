package Note::Row;
use strict;
use warnings;

use vars qw($Database);

use Data::Dumper;
use Scalar::Util 'reftype';
use Note::Param;
use Note::SQL::Database;
use Note::SQL::Sequence;

sub new
{
	my ($class, $table, $lkup, @extra) = @_;
	my $param = (ref($extra[0])) ? $extra[0] : {@extra};
	my $db = $param->{'database'} || $Database;
	my $fields = $param->{'select'} || ['id'];
	unless ($db->isa('Note::SQL::Database'))
	{
		die(q|Invalid database|);
	}
	unless (defined $table)
	{
		die(q|Undefined table|);
	}
	unless (ref($fields) && reftype($fields) eq 'ARRAY')
	{
		die(q|Invalid fields to select|);
	}
	unless (scalar grep /^id$/, @$fields)
	{
		push @$fields, 'id';
	}
	my $obj = {
		'select' => $fields,
		'table' => $db->table($table),
	};
	bless $obj, $class;
	if ($lkup =~ /^\d+$/)
	{
		$obj->{'id'} = $lkup;
	}
	elsif (ref($lkup) && (reftype($lkup) eq 'HASH') || (reftype($lkup) eq 'ARRAY'))
	{
		# lookup now
		my $res = $obj->_query($lkup);
		unless (defined $res)
		{
			$obj->{'id'} = undef;
		}
	}
	else
	{
		die(q|Invalid row lookup parameters|);
	}
	return $obj;
}

sub _query
{
	my ($obj, $whr) = @_;
	my $res = $obj->{'table'}->get(
		'hash' => 1,
		'select' => $obj->{'select'},
		'where' => $whr,
		'order' => 'id desc limit 1',
	);
	if (scalar @$res)
	{
		my $row = $res->[0];
		unless (ref($obj->{'select'}))
		{
			$obj->{'select'} = [$obj->{'select'}];
		}
		if (scalar grep /^(id|\*)$/, @{$obj->{'select'}})
		{
			$obj->{'id'} = $row->{'id'};
		}
		$obj->{'cache'} ||= {};
		%{$obj->{'cache'}} = (
			%{$obj->{'cache'}},
			%{$row},
		);
	}
	return $res->[0];
}

sub id
{
	my ($obj) = shift;
	return $obj->{'id'};
}

sub valid
{
	my ($obj) = shift;
	return 0 unless (defined $obj->{'id'});
	my $res = $obj->{'table'}->get(
		'array' => 1,
		'select' => 'count(id)',
		'where' => {
			'id' => $obj->{'id'},
		},
	);
	return 1 if ($res->[0]->[0]);
	return 0;
}

sub update
{
	my ($obj, $update) = @_;
	unless (ref($update) && reftype($update) eq 'HASH')
	{
		die('Invalid update data');
	}
	unless (defined $obj->{'id'})
	{
		die('Unknown record id to update');
	}
	return $obj->{'table'}->set(
		'update' => $update,
		'where' => {
			'id' => $obj->{'id'},
		},
	);
}

sub data
{
	my ($obj, @datakeys) = @_;
	if (scalar @datakeys)
	{
		my $rec = {};
		my @getkeys = ();
		foreach my $k (@datakeys)
		{
			if (exists $obj->{'cache'}->{$k})
			{
				$rec->{$k} = $obj->{'cache'}->{$k};
			}
			else
			{
				push @getkeys, $k;
			}
		}
		if (scalar @getkeys)
		{
			$obj->{'select'} = \@getkeys;
			my $data = $obj->_query({
				'id' => $obj->{'id'},
			});
			unless (defined $data)
			{
				die(qq|Row id: '$obj->{'id'}' not found in table: '|. $obj->{'table'}->table(). q|'|);
			}
			$data ||= {};
			$rec = {%$rec, %$data};
		}
		if (defined($rec) && scalar(@datakeys) == 1)
		{
			return $rec->{$datakeys[0]};
		}
		return $rec;
	}
	else
	{
		$obj->{'select'} = '*';
		my $data = $obj->_query({
			'id' => $obj->{'id'},
		});
		unless (defined $data)
		{
			die(qq|Row id: '$obj->{'id'}' not found in table: '|. $obj->{'table'}->table(). q|'|);
		}
		return $data;
	}
}

sub row
{
	my ($obj, $fkcol, $fktable) = @_;
	my $dv = $obj->data($fkcol);
	if (defined($dv) && $dv =~ /^\d+$/)
	{
		return new Note::Row($fktable, $dv);
	}
	elsif (! defined ($dv))
	{
		return undef;
	}
	else
	{
		die(qq|Invalid foreign key in col: '$fkcol' for row id: '$obj->{'id'}' in table: '|. $obj->{'table'}->table(). q|'|);
	}
}

# static method
sub create
{
	my ($table, $data, @extra) = @_;
	unless (ref($data) && reftype($data) eq 'HASH')
	{
		die('Invalid create data');
	}
	my $param = (ref($extra[0])) ? $extra[0] : {@extra};
	my $db = $param->{'database'} || $Database;
	my $seq = $param->{'sequence'};
	unless (defined $seq)
	{
		$seq = new Note::SQL::Sequence('database' => $db);
	}
	my $id = $seq->nextid();
	$data->{'id'} = $id;
	my $tbl = $db->table($table);
	$tbl->set(
		'insert' => $data,
	);
	my $nc = {
		'id' => $id,
		'table' => $tbl,
		'cache' => $data,
		'select' => 'id',
	};
	bless $nc, 'Note::Row';
	return $nc;
}

# static method
sub find_insert
{
	my ($table, $data, $extra, $create) = @_;
	unless (ref($data) && reftype($data) eq 'HASH')
	{
		die('Invalid find_insert data');
	}
	my $rc = new Note::Row($table, $data);
	unless (defined $rc->id())
	{
		if (defined ($extra) && reftype($extra) eq 'HASH')
		{
			$data = {%$data, %$extra};
		}
		if (ref ($create) && reftype($create) eq 'SCALAR')
		{
			$$create = 1;
		}
		$rc = Note::Row::insert($table, $data);
	}
	return $rc;
}

# static method
sub insert
{
	my ($table, $data, @extra) = @_;
	unless (ref($data) && reftype($data) eq 'HASH')
	{
		die('Invalid insert data');
	}
	my $param = (ref($extra[0])) ? $extra[0] : {@extra};
	my $db = $param->{'database'} || $Database;
	my $tbl = $db->table($table);
	$tbl->set(
		'insert' => $data,
	);
	my $id = $tbl->last_insert_id();
	my $nc = {
		'id' => $id,
		'table' => $tbl,
		'cache' => $data,
		'select' => 'id',
	};
	bless $nc, 'Note::Row';
	return $nc;
}

# static method
sub find_create
{
	my ($table, $data, $extra, $create) = @_;
	unless (ref($data) && reftype($data) eq 'HASH')
	{
		die('Invalid find_create data');
	}
	my $rc = new Note::Row($table, $data);
	unless (defined $rc->id())
	{
		if (defined ($extra) && reftype($extra) eq 'HASH')
		{
			$data = {%$data, %$extra};
		}
		if (ref ($create) && reftype($create) eq 'SCALAR')
		{
			$$create = 1;
		}
		$rc = Note::Row::create($table, $data);
	}
	return $rc;
}

sub delete
{
	my ($obj) = shift;
	$obj->{'table'}->delete(
		'where' => {
			'id' => $obj->id(),
		},
	);
}

# static method
sub table
{
	return $Database->table(@_);
}

1;
