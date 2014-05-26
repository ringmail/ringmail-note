package Note::XML;
use strict;
use warnings;

use base 'Exporter';
use vars qw(@EXPORT_OK);
@EXPORT_OK = ('xml');

# static method
#  takes an array of an XML tree structure - see XML::Parser, style: Tree
#  then the tree structure is converted into a string
sub xml
{
	my (@xmldata) = @_;
	my $result = '';
	unshift @xmldata, undef;
	_xml(\$result, \@xmldata);
	return $result;
}

sub _xml
{
	my $data = shift;
	my $list = shift;
	my $i = 0;
	while ($i < $#{$list})
	{
		my $k = $list->[++$i];
		my $v = $list->[++$i];
		if ($k eq '0')
		{
			if (defined $v)
			{
				$$data .= $v;
			}
		}
		else
		{ 
			my $args = $v->[0];
			my $argtxt = '';
			foreach my $i (sort keys %$args)
			{
				unless (defined $args->{$i})
				{
					$args->{$i} = '';
				}
				$argtxt .= " $i=\"". $args->{$i}. "\"";
			}
			$$data .= '<'. $k. $argtxt;
			if ($#{$v} > 0)
			{
				$$data .= '>';
				_xml($data, $v);
				$$data .= '</'. $k. '>';
			}
			else
			{
				$$data .= '/>';
			}
		}
	}
}

1;

