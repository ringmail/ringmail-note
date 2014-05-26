package Note::HTML;
use strict;
use warnings;

use base 'Exporter';
use vars qw(@EXPORT_OK);
@EXPORT_OK = ('htable', 'vtable', 'html_table');

use Note::XML 'xml';

# params:
#  fields
#  data
#  array
#  opts
#  opts_row
#  opts_col
#  opts_hcol
#  tag
#  tag_row
#  tag_col
#  tag_hcol
sub htable
{
	my (%input) = @_;
	my $param = \%input;
	my @html = ();
	my $tag_table = (exists $param->{'tag'}) ? $param->{'tag'} : 'table';
	my $tag_row = (exists $param->{'tag_row'}) ? $param->{'tag_row'} : 'tr';
	my $tag_col = (exists $param->{'tag_col'}) ? $param->{'tag_col'} : 'td';
	my $tag_hcol = (exists $param->{'tag_hcol'}) ? $param->{'tag_hcol'} : 'th';
	my $opts_table = $param->{'opts'};
	unless (ref($opts_table) && $opts_table =~ /HASH/)
	{
		$opts_table = {};
	}
	my $opts_row = $param->{'opts_row'};
	unless (ref($opts_row) && $opts_row =~ /HASH/)
	{
		$opts_row = {};
	}
	if (ref($param->{'fields'}) && $param->{'fields'} =~ /ARRAY/)
	{
		my $opts_field = $param->{'opts_row'};
		unless (ref($opts_row) && $opts_row =~ /HASH/)
		{
			$opts_field = {};
		}
		my @row = ();
		foreach my $i (@{$param->{'fields'}})
		{
			my $c = cell({
				'tag' => $tag_hcol,
				'opts'  => $param->{'opts_hcol'},
				'data' => $i,
				(($param->{'array'}) ? ('array' => 1) : ()),
			});
			if (ref($c))
			{
				push @row, @$c;
			}
			else
			{
				push @row, 0, $c;
			}
		}
		push @html, 'thead', [{}, $tag_row, [$opts_row, @row]];
	}
	my @body = ();
	if (ref($param->{'data'}) && $param->{'data'} =~ /ARRAY/)
	{
		foreach my $row (@{$param->{'data'}})
		{
			my $opts_this_row = {%$opts_row};
			if (ref($row) && $row =~ /HASH/)
			{
				if (ref($row->{'opts'}) && $row->{'opts'} =~ /HASH/)
				{
					$opts_this_row = {%$opts_this_row, %{$row->{'opts'}}};
				}
				$row = $row->{'data'};
			}
			if (ref($row) && $row =~ /ARRAY/)
			{
				my @row = ();
				foreach my $col (@$row)
				{
					my $c = cell({
						'tag' => $tag_col,
						'opts' => $param->{'opts_col'},
						'data' => $col,
						(($param->{'array'}) ? ('array' => 1) : ()),
					});
					if (ref($c))
					{
						push @row, @$c;
					}
					else
					{
						push @row, 0, $c;
					}
				}
				push @body, $tag_row, [$opts_this_row, @row];
			}
		}
	}
	push @html, 'tbody', [{}, @body];
	my @tbl = ($tag_table, [$opts_table, @html]);
	if ($param->{'array'})
	{
		return \@tbl;
	}
	else
	{
		return xml(@tbl);
	}
}

sub vtable
{
	my (%input) = @_;
	my $param = \%input;
	my @html = ();
	my $tag_table = (exists $param->{'tag'}) ? $param->{'tag'} : 'table';
	my $tag_row = (exists $param->{'tag_row'}) ? $param->{'tag_row'} : 'tr';
	my $tag_col = (exists $param->{'tag_col'}) ? $param->{'tag_col'} : 'td';
	my $tag_hcol = (exists $param->{'tag_hcol'}) ? $param->{'tag_hcol'} : 'th';
	my $opts_table = $param->{'opts'};
	unless (ref($opts_table) && $opts_table =~ /HASH/)
	{
		$opts_table = {};
	}
	my $opts_row = $param->{'opts_row'};
	unless (ref($opts_row) && $opts_row =~ /HASH/)
	{
		$opts_row = {};
	}
	if (ref($param->{'fields'}) && $param->{'fields'} =~ /ARRAY/)
	{
		if (ref($param->{'data'}) && $param->{'data'} =~ /ARRAY/)
		{
			my $data = $param->{'data'};
			if ($param->{'rotate'})
			{
				$data = rotate($data);
			}
			foreach my $rid (0..$#{$data})
			{
				my $row = $data->[$rid];
				my $opts_this_row = {%$opts_row};
				if (ref($row) && $row =~ /HASH/)
				{
					if (ref($row->{'opts'}) && $row->{'opts'} =~ /HASH/)
					{
						$opts_this_row = {%$opts_this_row, %{$row->{'opts'}}};
					}
					$row = $row->{'data'};
				}
				my @row = ();
				if (exists $param->{'fields'}->[$rid])
				{
					my $c = cell({
						'tag' => $tag_hcol,
						'opts' => $param->{'opts_hcol'},
						'data' => $param->{'fields'}->[$rid],
						(($param->{'array'}) ? ('array' => 1) : ()),
					});
					if (ref($c))
					{
						push @row, @$c;
					}
					else
					{
						push @row, 0, $c;
					}
				}
				else
				{
					my $c = cell({
						'tag' => $tag_col,
						'opts' => $param->{'opts_col'},
						'data' => [],
						(($param->{'array'}) ? ('array' => 1) : ()),
					});
					if (ref($c))
					{
						push @row, @$c;
					}
					else
					{
						push @row, 0, $c;
					}
				}
				if (ref($row) && $row =~ /ARRAY/)
				{
					foreach my $col (@$row)
					{
						my $c = cell({
							'tag' => $tag_col,
							'opts' => $param->{'opts_col'},
							'data' => $col,
							(($param->{'array'}) ? ('array' => 1) : ()),
						});
						if (ref($c))
						{
							push @row, @$c;
						}
						else
						{
							push @row, 0, $c;
						}
					}
					push @html, $tag_row, [$opts_this_row, @row];
				}
			}
		}
	}
	my @tbl = ($tag_table, [$opts_table, @html]);
	if ($param->{'array'})
	{
		return \@tbl;
	}
	else
	{
		return xml(@tbl);
	}
}

sub html_table
{
	my (%input) = @_;
	my $param = \%input;
	my @html = ();
	my $tag_table = (exists $param->{'tag'}) ? $param->{'tag'} : 'table';
	my $tag_row = (exists $param->{'tag_row'}) ? $param->{'tag_row'} : 'tr';
	my $tag_col = (exists $param->{'tag_col'}) ? $param->{'tag_col'} : 'td';
	my $tag_hcol = (exists $param->{'tag_hcol'}) ? $param->{'tag_hcol'} : 'th';
	my $opts_table = $param->{'opts'};
	unless (ref($opts_table) && $opts_table =~ /HASH/)
	{
		$opts_table = {};
	}
	my $opts_row = $param->{'opts_row'};
	unless (ref($opts_row) && $opts_row =~ /HASH/)
	{
		$opts_row = {};
	}
	if (ref($param->{'data'}) && $param->{'data'} =~ /ARRAY/)
	{
		foreach my $row (@{$param->{'data'}})
		{
			my $opts_this_row = {%$opts_row};
			if (ref($row) && $row =~ /HASH/)
			{
				if (ref($row->{'opts'}) && $row->{'opts'} =~ /HASH/)
				{
					$opts_this_row = {%$opts_this_row, %{$row->{'opts'}}};
				}
				$row = $row->{'data'};
			}
			if (ref($row) && $row =~ /ARRAY/)
			{
				my @row = ();
				foreach my $col (@$row)
				{
					my $c = cell({
						'tag' => $tag_col,
						'opts' => $param->{'opts_col'},
						'data' => $col,
						(($param->{'array'}) ? ('array' => 1) : ()),
					});
					if (ref($c))
					{
						push @row, @$c;
					}
					else
					{
						push @row, 0, $c;
					}
				}
				push @html, $tag_row, [$opts_this_row, @row];
			}
		}
	}
	my @tbl = ($tag_table, [$opts_table, @html]);
	if ($param->{'array'})
	{
		return \@tbl;
	}
	else
	{
		return xml(@tbl);
	}

}

sub cell
{
	my $param = shift;
	die 'Invalid parameters' unless (ref($param) && $param =~ /HASH/);
	my $data = $param->{'data'};
	if (ref($data) and $data =~ /HASH/)
	{
		$param = {%$param, %$data};
		$data = $param->{'data'};
	}
	my $tag = $param->{'tag'};
	my $opts = $param->{'opts'};
	$opts = {} unless (ref($opts) && $opts =~ /HASH/);
	my @cell = ();
	if (ref($data) && $data =~ /ARRAY/)
	{
		@cell = ($tag, [$opts, @$data]);
	}
	else
	{
		@cell = ($tag, [$opts, 0, $data]);
	}
	if ($param->{'array'})
	{
		return \@cell;
	}
	else
	{
		return xml(@cell);
	}
}

sub rotate
{
	my $q = shift;
	my $v = [];
	foreach my $i (0..$#{$q})
	{
		my $r = $q->[$i];
		foreach my $j (0..$#{$r})
		{   
			$v->[$j]->[$i] = $r->[$j];
		}
	} 
	return $v;
}

1;

