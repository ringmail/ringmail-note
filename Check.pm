package Note::Check;
use strict;
use warnings;
no warnings qw(uninitialized);

use base 'Exporter';
use vars qw(@EXPORT %check_type);
@EXPORT = qw(check_type check_fields);

use Data::Dumper;

our %check_type = ();

###
# check_fields
# Apply a set of checks to the fields in a hashref
###
# Input:
#   hashref of checks
#     - keys match data keys
#     - each value can be a check
#       or an arrayref of them
#   hashref of data to check
#   scalarref for error return
# Output:
#   1 if all checks pass, 0 otherwise
###
sub check_fields
{
	my ($consts, $data, $err) = @_;
	unless (ref($consts) && $consts =~ /HASH/)
	{
		die('Invalid parameters');
	}
	unless (ref($data) && $data =~ /HASH/)
	{
		die('Invalid parameters');
	}
	foreach my $k (sort keys %$consts)
	{
		my $cr = $consts->{$k};
		if (ref($cr) && $cr =~ /ARRAY/)
		{
			foreach my $c (@$cr)
			{
				unless ($c->check(\$data->{$k}))
				{
					if (ref($err) && $err =~ /SCALAR/)
					{
						$$err = $c->error();
					}
					return 0;
				}				
			}
		}
		else
		{
			unless ($cr->check(\$data->{$k}))
			{
				if (ref($err) && $err =~ /SCALAR/)
				{
					$$err = $cr->error();
				}
				return 0;
			}
		}
	}
	return 1;
}

sub new
{
	my ($class, @inp) = @_;
	my $def = (ref($inp[0])) ? $inp[0] : {@inp};
	unless (ref($def) && $def =~ /HASH/)
	{
		die('Invalid parameters');
	}
	bless $def, $class;
	return $def;
}

sub fail
{
	my ($msg) = @_;
	die($msg. '~~');
}

sub error
{
	my ($obj) = @_;
	return $obj->{'error'};
}

sub check
{
	my ($obj, $data) = @_;
	return check_type($obj->{'type'}, $obj, $data);
}

sub valid
{
	my $obj = shift;
	return $obj->check(@_);
}

sub check_type
{
	my ($type, $param, $data) = @_;
	unless (ref($param) && $param =~ /HASH/)
	{
		fail('Invalid parameters');
	}
	unless (ref($data) && $data =~ /SCALAR/)
	{
		fail('Invalid value reference');
	}
	if (exists $check_type{$type})
	{
		my $pass = undef;
		eval {
			$pass = $check_type{$type}->($param, $data);
		};
		if ($@)
		{
			my $err = $@;
			$err =~ s/(\r|\n)//g;
			$err =~ s/\~\~.*//m;
			$param->{'error'} = $err;
		}
		return $pass;
	}
	else
	{
		fail("Unknown check: $type");
	}
}

END: {
	$check_type{'valid'} = sub {
		my ($param, $data) = @_;
		unless (ref($param->{'valid'}) eq 'CODE')
		{
			fail('Undefined validation');
		}
		return $param->{'valid'}->($param, $data);
	};
	$check_type{'boolean'} = sub {
		my ($param, $data) = @_;
		my %ok = (
			'0' => 0,
			'false' => 0,
			'no' => 0,
			'' => 0,
			'1' => 1,
			'true' => 1,
			'yes' => 1,
			'on' => 1,
		);
		my $val = '';
		if (length($$data))
		{
			$val = lc($$data);
		}
		if (exists $ok{$val})
		{
			$$data = $ok{$val};
			return 1;
		}
		else
		{
			fail('Invalid boolean');
		}
	};
	$check_type{'integer'} = sub {
		my ($param, $data) = @_;
		my $val = $$data;
		if ($val =~ /[^0-9\s\,\-]/)
		{
			fail('Invalid integer');
		}
		$val =~ s/[^0-9\-]//g;
		$$data = $val;
		if (exists $param->{'max'})
		{
			if ($val > $param->{'max'})
			{
				fail('Value above maximum');
			}
		}
		if (exists $param->{'min'})
		{
			if ($val < $param->{'min'})
			{
				fail('Value below minimum');
			}
		}
		return 1;
	};
	$check_type{'float'} = sub {
		my ($param, $data) = @_;
		my $val = $$data;
		if ($val =~ /[^0-9\s\,\-\.]/)
		{
			fail('Invalid float');
		}
		$val =~ s/[^0-9\-\.]//g;
		$$data = $val;
		if (exists $param->{'max'})
		{
			if ($val > $param->{'max'})
			{
				fail('Value above maximum');
			}
		}
		elsif (exists $param->{'min'})
		{
			if ($val < $param->{'min'})
			{
				fail('Value below minimum');
			}
		}
		return 1;
	};
	$check_type{'currency'} = sub {
		my ($param, $data) = @_;
		my $val = $$data;
		unless ($val =~ /^\d+(\.\d\d)?$/)
		{
			fail('Invalid currency value');
		}
		if (exists $param->{'max'})
		{
			if ($val > $param->{'max'})
			{
				fail('Value above maximum');
			}
		}
		elsif (exists $param->{'min'})
		{
			if ($val < $param->{'min'})
			{
				fail('Value below minimum');
			}
		}
		return 1;
	};
	$check_type{'regex'} = sub {
		my ($param, $data) = @_;
		if (exists $param->{'chars'})
		{
			my $regex = '';
			my $chrs = $param->{'chars'};
			if ($chrs =~ s/(a\-z)//)
			{
				$regex .= 'a-z';
			}
			if ($chrs =~ s/(A\-Z)//)
			{
				$regex .= 'A-Z';
			}
			if ($chrs =~ s/0\-9//)
			{
				$regex .= '0-9'; 
			}
			my @chrs = split //, $chrs;
			my %seen = ();
			foreach my $c (@chrs)
			{
				next if ($seen{$c}++);
				$regex .= quotemeta($c);
			}
			if ($param->{'chars_inverse'})
			{
				$regex = '^'. $regex;
			}
			my $empty = '*';
			unless ($param->{'chars_empty'})
			{
				$empty = '+';
			}
			$regex = "^[$regex]". $empty. '$';
			if ($param->{'chars_ignore_case'})
			{
				$param->{'regex'} = qr/$regex/i;
			}
			else
			{
				$param->{'regex'} = qr/$regex/;
			}
		}
		my $re = $param->{'regex'};
		unless (ref($re) eq 'Regexp')
		{
			fail('Invalid regex');
		}
		my $match = ($$data =~ /$re/);
		if ($param->{'inverse'})
		{
			if ($match)
			{
				fail('Invalid characters');
			}
			else
			{
				return 1;
			}
		}
		elsif ($match)
		{
			return 1;
		}
		elsif ($param->{'empty'} && $$data eq '')
		{
			return 1;
		}
		else
		{
			fail('Invalid characters');
		}
	};
	$check_type{'in'} = sub {
		my ($param, $data) = @_;
		my $val = $$data;
		my @valid = @{$param->{'valid'}};
		if ((grep { m/^$val$/ } @valid) < 1)
		{
			fail('Value not in selection');
		}
		return 1;
	};
	$check_type{'text'} = sub {
		my ($param, $data) = @_;
		if ($$data =~ /^[A-Za-z0-9.\?\!\@\,\-\_\s\(\)\[\]\$\#\%\*\^\=\+\/\\\:\;\']+$/m)
		{
			return 1;	
		} 
		fail('Invalid characters. Do not use < > or &');
	};
}

1;
