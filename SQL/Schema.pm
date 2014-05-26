package Note::SQL::Schema;
use strict;
use warnings;
no warnings 'uninitialized';

use Moose;
use Data::Dumper;
use Scalar::Util 'blessed';
use SQL::Translator;

use Note::Param;

has 'data' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'default' => sub {
		return {
			'field' => {},
			'index' => {},
		};
	},
);

has 'format' => (
	'is' => 'rw',
	'isa' => 'Str',
);

sub sql_create_table
{
	my ($obj, $param) = get_param(@_);
	my $translator = new SQL::Translator(
		'no_comments' => 1,
	);
	my $data = $obj->data();
	my $fmt = $obj->format();
	if ($fmt =~ /^mysql$/i)
	{
		$translator->parser(sub {
			my ($tr) = @_;
			my $schema = $tr->schema();
			my $table = SQL::Translator::Schema::Table->new(
				'name' => $data->{'name'},
			);
			my $prik = undef;
			if (exists $data->{'primary_key'})
			{
				if ($data->{'primary_key'})
				{
 					# TODO: multi-column primary keys
					unless (ref($data->{'primary_key'}))
					{
						my $prik = $data->{'primary_key'};
						my $fld = $data->{'field'}->{$prik};
						$obj->sql_create_field($table, $prik, $fld);
						$table->primary_key($prik);
					}
				}
			}
			else
			{
				$table->add_field(
					'name' => 'id',
					'data_type' => 'bigint',
				);
				my $pk = $table->get_field('id');
				$pk->extra({'unsigned' => 1});
				$pk->is_nullable(0);
				$table->primary_key('id');
				$prik = 'id';
			}
			$table->options({
				'ENGINE' => 'InnoDB',
			});
			$table->options({
				'DEFAULT CHARSET' => 'latin1',
			});
			foreach my $k (sort keys %{$data->{'field'}})
			{
				next if ($k eq $prik);
				my $fld = $data->{'field'}->{$k};
				$obj->sql_create_field($table, $k, $fld);
			}
			foreach my $ik (sort keys %{$data->{'index'}})
			{
				my $idata = $data->{'index'}->{$ik};
				my $ty = 'NORMAL';
				if ($idata->{'type'} eq 'unique')
				{
					$ty = 'UNIQUE';
				}
				$table->add_index(
					'name' => $ik,
					'type' => $ty,
					'fields' => [@{$idata->{'fields'}}],
				);
			}
			$schema->add_table($table);
			return 1;
		});
		my $sql = $translator->translate(
			'producer' => 'MySQL',
			'producer_args' => {
				'mysql_version' => 5,
			},
		);
		unless (defined $sql)
		{
			die (qq|SQL translate error|);
		}
		# move the backslash to the right spot
		while ($sql =~ s/^(.*?index.*?)\((\d+)\)\`/$1`($2)/im) { 1; }
		my @pts = split /\n\n/, $sql;
		return $pts[1];
	}
	else
	{
		die (qq|Unknown SQL database format: '$fmt'|);
	}
}

sub sql_create_field
{
	my ($obj, $table, $k, $fld) = @_;
	my $type = $fld->{'type'};
	my $sqltype;
	my %extra = ();
	if ($type eq 'text')
	{
		my $sz = $fld->{'length'};
		if ($sz <= 255)
		{
			$sqltype = 'varchar('. $sz. ')';
		}
		elsif ($sz <= 65535)
		{
			$sqltype = 'text';
		}
		else
		{
			$sqltype = 'longtext';
		}
	}
	elsif ($type eq 'binary')
	{
		my $sz = $fld->{'length'};
		if ($sz <= 255)
		{
			$sqltype = 'varbinary('. $sz. ')';
		}
		elsif ($sz <= 65535)
		{
			$sqltype = 'blob';
		}
		else
		{
			$sqltype = 'longblob';
		}
	}
	elsif ($type eq 'record')
	{
		$extra{'unsigned'} = 1;
		$sqltype = 'bigint';
	}
	elsif ($type eq 'boolean')
	{
		$sqltype = 'bool';
	}
	elsif ($type eq 'integer')
	{
		$sqltype = 'bigint';
	}
	elsif ($type eq 'float')
	{
		$sqltype = 'real';
	}
	elsif ($type eq 'currency')
	{
		$sqltype = 'decimal(24,4)';
	}
	elsif ($type eq 'date' || $type eq 'datetime')
	{
		if ($fld->{'default'} eq 'now')
		{
			$sqltype = 'timestamp';
		}
		else
		{
			$sqltype = $type;
		}
	}
	$table->add_field(
		'name' => $k,
		'data_type' => $sqltype,
	);
	my $field = $table->get_field($k);
	if ($fld->{'optional'})
	{
		$field->is_nullable(1);
	}
	else
	{
		$field->is_nullable(0);
	}
	if (scalar keys %extra)
	{
		foreach my $i (sort keys %extra)
		{
			$field->extra($i => $extra{$i});
		}
	}
	if ($type eq 'date' || $type eq 'datetime')
	{
		if ($fld->{'default'} eq 'now')
		{
			$field->default_value(\'CURRENT_TIMESTAMP');
		}
		elsif (length($fld->{'default'}))
		{
			$field->default_value($fld->{'default'});
		}
	}
	elsif ($type eq 'boolean')
	{
		my $def = ($fld->{'default'}) ? 1 : 0;
		$field->default_value(\$def);
	}
	elsif (exists($fld->{'default'}) && length($fld->{'default'}))
	{
		$field->default_value($fld->{'default'});
	}
}

sub decode_sql
{
}

1;

