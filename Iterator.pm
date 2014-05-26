package Note::Iterator;
use strict;
use warnings;
no warnings qw(uninitialized);

use Moose;
use Scalar::Util qw(reftype);
use Note::Param;
use Iterator;
use Iterator::IO;
use Iterator::Util;
use Text::CSV_XS;

has 'iterator' => (
	'is' => 'rw',
	'isa' => 'Iterator',
	'lazy' => 1,
	'default' => sub {
		my ($obj) = shift;
		return new Iterator($obj->code()),
	},
);

has 'code' => (
	'is' => 'rw',
	'isa' => 'CodeRef',
);

has 'translate' => (
	'is' => 'rw',
	'isa' => 'CodeRef',
);

has 'grep' => (
	'is' => 'rw',
	'isa' => 'CodeRef',
);

has 'fields' => (
	'is' => 'rw',
	'isa' => 'ArrayRef',
	'default' => sub { return []; },
);

has 'count' => (
	'is' => 'rw',
	'isa' => 'Int',
	'default' => sub { return 0; },
);

has 'translated' => (
	'is' => 'rw',
	'isa' => 'Int',
	'default' => sub { return 0; },
);

has 'matched' => (
	'is' => 'rw',
	'isa' => 'Int',
	'default' => sub { return 0; },
);

has 'skipped' => (
	'is' => 'rw',
	'isa' => 'Int',
	'default' => sub { return 0; },
);

sub BUILD
{
	my ($obj, $param) = @_;
	my $iter = undef;
	if (exists $param->{'list'} && reftype($param->{'list'}) eq 'ARRAY')
	{
		$iter = ilist(@{$param->{'list'}});
	}
	elsif (exists $param->{'array'} && reftype($param->{'array'}) eq 'ARRAY')
	{
		$iter = iarray($param->{'array'});
	}
	elsif (exists $param->{'hash'} && reftype($param->{'hash'}) eq 'HASH')
	{
		my @ks = (sort keys %{$param->{'hash'}});
		$iter = iarray(\@ks);
	}
	elsif (exists $param->{'file'})
	{
		my @ops = ();
		if (exists $param->{'opts'} && reftype($param->{'opts'}) eq 'HASH')
		{
			my %opts = (%{$param->{'opts'}});
			push @ops, \%opts;
		}
		$iter = ifile($param->{'file'}, @ops);
		if (exists $param->{'type'})
		{
			if ($param->{'type'} eq 'csv')
			{
				$obj->iterator($iter);
				$obj->build_csv_closure($param);
			}
		}
	}
	elsif (exists $param->{'code'} && reftype($param->{'code'}) eq 'CODE')
	{
		$obj->code($param->{'code'});
		return; # lazy
	}
	if (defined $iter)
	{
		$obj->iterator($iter);
	}
	elsif (! defined $obj->iterator())
	{
		die('No data for iterator');
	}
}

sub build_csv_closure
{
	my ($obj, $param) = get_param(@_);
	my @csvops = ();
	if (exists $param->{'csv_opts'} && reftype($param->{'csv_opts'}) eq 'HASH')
	{
		my %opts = (%{$param->{'csv_opts'}});
		push @csvops, \%opts;
	}
	else
	{
		@csvops = ({
			'binary' => 1,
		});
	}
	my $csvobj = new Text::CSV_XS(@csvops);
	if ($param->{'csv_fields'})
	{
		if ($param->{'csv_fields'} eq '1')
		{
			my $firstline = $obj->iterator()->value();
			$firstline =~ s/(\r|\n)//g;
			$csvobj->parse($firstline);
			my @flds = $csvobj->fields();
			$obj->fields(\@flds);
		}
		elsif (reftype($param->{'csv_fields'}) eq 'ARRAY')
		{
			$obj->fields($param->{'csv_fields'});
		}
	}
	my @fields = @{$obj->fields()};
	my $hasfields = scalar(@fields);
	$obj->translate(sub {
		my ($line) = @_;
		$line =~ s/(\r|\n)//g;
		$csvobj->parse($line);
		my @d = $csvobj->fields();
		if ($hasfields)
		{
			my %rc = map {$fields[$_] => $d[$_]} (0..$#fields);
			return \%rc;
		}
		else
		{
			return \@d;
		}
	});
}

sub has_next
{
	my $obj = shift;
	return $obj->iterator()->isnt_exhausted();
}

sub get_value
{
	my $obj = shift;
	my $val = undef;
	eval {
		$val = $obj->iterator()->value();
	};
	if (my $ex = Iterator::X->caught())
	{
		if ($ex->isa('Iterator::X::Exhausted'))
		{
			return undef;
		}
		elsif ($ex->isa('Iterator::X::User_Code_Error'))
		{
			die(qq|Iterator code error: |. $ex->eval_error());
		}
		elsif ($ex->isa('Iterator::X::IO_Error'))
		{
			die(qq|Iterator io error: |. $ex->os_error());
		}
		elsif ($ex->isa('Iterator::X::Internal_Error'))
		{
			die(qq|Iterator internal error|);
		}
		elsif ($ex->isa('Iterator::X::Parameter_Error'))
		{
			die(qq|Iterator parameter error|);
		}
		else
		{
			warn("error");
			$ex->rethrow();
		}
	}
	$obj->{'count'}++;
	return \$val;
}

sub translate_value
{
	my ($obj, $valref) = @_;
	my $trs = $obj->translate();
	if (defined $trs)
	{
		eval {
			$$valref = $trs->($$valref);
		};
		if ($@)
		{
			die('Iterator data translation failed: '. $@);
		}
		$obj->{'translated'}++;
	}
}

sub grep_value
{
	my ($obj, $valref) = @_;
	my $grepfn = $obj->grep();
	if (defined $grepfn)
	{
		my $v = $$valref;
		my $match = $grepfn->($v);
		while (! $match)
		{
			$obj->{'skipped'}++;
			my $nv = $obj->get_value();
			if (defined $nv)
			{
				$obj->translate_value($nv);
				$match = $grepfn->($$nv);
				if ($match)
				{
					$v = $$nv;
				}
			}
			else
			{
				return undef;
			}
		}
		if ($match)
		{
			$obj->{'matched'}++;
		}
		$$valref = $v;
	}
	else
	{
		return 1;
	}
}

sub value
{
	my $obj = shift;
	my $valref = $obj->get_value();
	return undef unless (defined $valref);
	$obj->translate_value($valref);
	if (defined $obj->grep_value($valref))
	{
		return $$valref;
	}
	return undef;
}

1;

