package Note::SQL::Schema;
use strict;
use warnings;

use Moose;
use Data::Dumper;
use Scalar::Util 'blessed', 'reftype';
use SQL::Translator;

use Note::Param;

no strict 'refs';
no warnings 'uninitialized';

sub table_sql
{
	my ($obj, $name, $data, $schref, $platform) = @_;
	my $translator = new SQL::Translator(
		'no_comments' => 1,
	);
	$translator->parser(sub {
		my ($tr) = @_;
		my $schema = $tr->schema();
		my $table = SQL::Translator::Schema::Table->new(
			'name' => $name,
		);
		$table->add_field(
			'name' => 'id',
			'data_type' => 'bigint',
		);
		my $pk = $table->get_field('id');
		$pk->extra({'unsigned' => 1});
		$pk->is_nullable(0);
		if ($data->{'primary_key'}->{'mode'} eq 'auto_inc')
		{
			$pk->is_auto_increment(1);
		}
		$table->primary_key('id');
		$table->options({
			'ENGINE' => 'InnoDB',
		});
		$table->options({
			'DEFAULT CHARSET' => 'latin1',
		});
		foreach my $k (sort keys %{$data->{'columns'}})
		{
			my $fld = $data->{'columns'}->{$k};
			$obj->field_sql($table, $k, $fld);
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
				'fields' => [@{$idata->{'columns'}}],
			);
		}
                for my $constraint_name ( keys %{ $data->{constraint} } ) {
                    my $constraint = $data->{constraint}->{$constraint_name};
                    $table->add_constraint(

                        name             => $constraint_name,
                        type             => 'foreign key',
                        fields           => $constraint->{columns},
                        reference_table  => $constraint->{reference_table},
                        reference_fields => $constraint->{reference_columns},
                        on_update        => $constraint->{on_update},
                        on_delete        => $constraint->{on_delete},

                    );
                }
		$schema->add_table($table);
		if (ref($schref))
		{
			$$schref = $schema;
		}
		return 1;
	});
	my $sql = '';
	my @pts = ();
	$platform ||= 'mysql';
	if ($platform eq 'mysql')
	{
		$sql = $translator->translate(
			'producer' => 'MySQL',
			'producer_args' => {
				'mysql_version' => 5,
			},
		);
		unless (defined $sql)
		{
			die ('SQL translate error');
		}
		while ($sql =~ s/^(.*?index.*?)\((\d+)\)\`/$1`($2)/im) { 1; }
		@pts = split /\n\n/, $sql;
	}
	elsif ($platform eq 'sqlite')
	{
		$sql = $translator->translate(
			'producer' => 'SQLite',
		);
		@pts = (undef, $sql);
	}
	return $pts[1];
}

sub field_sql
{
	my ($obj, $table, $k, $fld) = @_;
	my $type = $fld->{'type'};
	my $sqltype;
	my %extra = ();
	if ($type eq 'text')
	{
		my $sz = $fld->{'length'};
		if ($sz =~ /^\d+$/ && $sz <= 255)
		{
			$sqltype = 'varchar('. $sz. ')';
		}
		elsif ($sz eq '64k')
		{
			$sqltype = 'text';
		}
		elsif ($sz eq 'long')
		{
			$sqltype = 'longtext';
		}
	}
	elsif ($type eq 'binary')
	{
		my $sz = $fld->{'length'};
		if ($sz =~ /^\d+$/ && $sz <= 255)
		{
			$sqltype = 'varbinary('. $sz. ')';
		}
		elsif ($sz eq '64k')
		{
			$sqltype = 'blob';
		}
		elsif ($sz eq 'long')
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
		$sqltype = 'tinyint(1)';
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
		$sqltype = 'decimal(24,2)';
	}
	elsif ($type eq 'date' || $type eq 'datetime')
	{
		if ($fld->{'timestamp'})
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
	if ($fld->{'null'})
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
		if ($fld->{'timestamp'})
		{
			$field->default_value(\'CURRENT_TIMESTAMP');
		}
		elsif ($fld->{'default_null'})
		{
			$field->default_value(\'NULL');
		}
	}
	elsif ($type eq 'boolean')
	{
		if ($fld->{'default_null'})
		{
			$field->default_value(\'NULL');
		}
		else
		{
			my $def = ($fld->{'default'}) ? '1' : '0';
			$field->default_value($def);
		}
	}
	elsif (
		($type eq 'text' && ! ($fld->{'length'} =~ /^\d+$/ && $fld->{'length'} <= 255)) ||
		($type eq 'binary' && ! ($fld->{'length'} =~ /^\d+$/ && $fld->{'length'} <= 255))
	) {
		# no default value in MySQL 5.6
	}
	elsif ((! $fld->{'default_null'}) && defined ($fld->{'default'}))
	{
		$field->default_value($fld->{'default'});
	}
	elsif ($type eq 'text' || $type eq 'binary')
	{
		if ($fld->{'default_null'})
		{
			$field->default_value(\'NULL');
		}
	}
	return $field->schema();
}

sub table_parse
{
	my ($obj, $sql, $trace) = @_;
	my $trns = new SQL::Translator();
	if ($trace)
	{
		$trns->trace(1);
	}
	$trns->parser(sub {
		my ($tr, $data) = @_;
		SQL::Translator::Parser::MySQL::parse($tr, $sql. ';');
		return 1;
	});
	return $trns->translate();
}

sub table_diff
{
	my ($obj, $currentsql, $newsql, $tname) = @_;
	$currentsql =~ s{ AUTO_INCREMENT=\d+}{}m;
	my $curschema = $obj->table_parse($currentsql);
	my $newschema = $obj->table_parse($newsql);
	foreach my $t ($curschema->get_tables())
	{
		foreach my $fld ($t->get_fields())
		{
			my $dt = $fld->data_type();
			my $dv = $fld->default_value();
			my $k = $fld->name();
			if ($dt eq 'bigint')
			{
				if (defined($dv) && $dv eq 'NULL')
				{
					$fld->default_value(undef);
				}
			}
		}
	}
	#my $dump = Dumper($curschema, $newschema);
	my $diff = SQL::Translator::Diff->new({
		'output_db' => 'MySQL',
		'source_schema' => $curschema,
		'target_schema' => $newschema,
		producer_args => { quote_identifiers => 1, },
		#%$options_hash,
	})->compute_differences()->produce_diff_sql();
	if ($diff =~ /-- No differences found;/m)
	{
		return undef;
	}
	#print $dump;
	$diff =~ s/^\s*--.*$//mg;
	$diff =~ s/^\s*\n//mg;
	$diff =~ s/^\s*(BEGIN|COMMIT);\s*\n//mg;
	return $diff;
}

sub table_from_sql
{
	my ($obj, $param) = get_param(@_);
	my $sql = $param->{'sql'};
	my %dbitypes = (map { &{"DBI::$_"}() => $_} @{$DBI::EXPORT_TAGS{'sql_types'}});
	my $schdata = $obj->table_parse($sql, $param->{'trace'});
	my $tables = [$schdata->get_tables()];
	unless (scalar(@$tables) == 1)
	{
		die("Invalid table specification");
	}
	my $t = $tables->[0];
	my $pkey = {};
	my $cols = {};
	my $idx = {};
	foreach my $fld ($t->get_fields())
	{
		my $f = $obj->field_from_sql(
			'field' => $fld,
			'dbi_types' => \%dbitypes,
		);
		if ($fld->is_primary_key()) # Composite keys not supported
		{
			$pkey->{'name'} = $f->{'name'};
			$pkey->{'type'} = $f->{'type'};
			if ($fld->is_auto_increment())
			{
				$pkey->{'mode'} = 'auto_inc';
			}
		}
		else
		{
			$cols->{$f->{'name'}} = $f;
		}
	}
	foreach my $index ($t->get_indices())
	{
		my $irec = {};
		$irec->{'name'} = $index->name();
		$irec->{'type'} = ($index->type() =~ /^unique$/i) ? 'unique' : 'index';
		my @flds = $index->fields();
		$irec->{'columns'} = \@flds;
		$idx->{$irec->{'name'}} = $irec;
	}
	foreach my $constr ($t->get_constraints())
	{
		my $irec = {};
		$irec->{'name'} = $constr->name();
		my $type = $constr->type();
		if ($type =~ /^primary key$/i)
		{
			next;
		}
		unless ($type =~ /^unique$/i)
		{
			die('Unknown constraint type: '. $constr->type());
		}
		$irec->{'type'} = 'unique';
		my @flds = $constr->field_names();
		$irec->{'columns'} = \@flds;
		$idx->{$irec->{'name'}} = $irec;
	}
	::log($idx);
	my $res = {
		'name' => $t->name(),
		'primary_key' => $pkey,
		'columns' => $cols,
		'index' => $idx,
	};
}

sub field_from_sql
{
	my ($obj, $param) = get_param(@_);
	my $fld = $param->{'field'};
	my $types = $param->{'dbi_types'};
	my $dt = $types->{$fld->sql_data_type()};
	my $extra = {$fld->extra()};
	my $res = {};
	$res->{'null'} = ($fld->is_nullable()) ? 1 : 0;
	my $def = $fld->default_value();
	if ($dt eq 'SQL_ALL_TYPES')
	{
		my $orig = $fld->data_type();
		if ($orig =~ /longtext/i)
		{
			$dt = 'NOTE_LONGTEXT';
		}
		elsif ($orig =~ /longblob/i)
		{
			$dt = 'NOTE_LONGBLOB';
		}
		elsif ($orig =~ /bool/i)
		{
			$dt = 'NOTE_BOOL';
		}
	}
	if (
		$dt eq 'SQL_CHAR' ||
		$dt eq 'SQL_VARCHAR' ||
		$dt eq 'SQL_LONGVARCHAR' ||
		$dt eq 'NOTE_LONGTEXT'
	) {
		if (
			$dt eq 'SQL_CHAR' ||
			$dt eq 'SQL_VARCHAR'
		) {
			$res->{'length'} = $fld->size();
		}
		elsif ($dt eq 'SQL_LONGVARCHAR')
		{
			$res->{'length'} = '64k';
		}
		elsif ($dt eq 'NOTE_LONGTEXT')
		{
			$res->{'length'} = 'long';
		}
		$dt = 'text';
	}
	elsif (
		$dt eq 'SQL_BINARY' ||
		$dt eq 'SQL_VARBINARY' ||
		$dt eq 'SQL_BLOB' ||
		$dt eq 'NOTE_LONGBLOB'
	) {
		if (
			$dt eq 'SQL_BINARY' ||
			$dt eq 'SQL_VARBINARY'
		) {
			$res->{'length'} = $fld->size();
		}
		elsif ($dt eq 'SQL_BLOB')
		{
			$res->{'length'} = '64k';
		}
		elsif ($dt eq 'NOTE_LONGBLOB')
		{
			$res->{'length'} = 'long';
		}
		$dt = 'binary';
	}
	elsif (
		$dt eq 'SQL_BIGINT'
	) {
		if ($res->{'null'} && $def eq 'NULL')
		{
			$def = undef;
		}
		if ($extra->{'unsigned'})
		{
			$dt = 'record';
		}
		else
		{
			$dt = 'integer';
		}
	}
	elsif (
		$dt eq 'SQL_BIGINT'
	) {
		if ($res->{'null'} && $def eq 'NULL')
		{
			$def = undef;
		}
		if ($extra->{'unsigned'})
		{
			$dt = 'record';
		}
		else
		{
			$dt = 'integer';
		}
	}
	elsif (
		$dt eq 'SQL_TINYINT' ||
		$dt eq 'NOTE_BOOL'
	) {
		$dt = 'boolean';
	}
	elsif (
		$dt eq 'SQL_INTEGER'
	) {
		$dt = 'integer';
	}
	elsif (
		$dt eq 'SQL_REAL' ||
		$dt eq 'SQL_DOUBLE'
	) {
		$dt = 'float';
	}
	elsif (
		$dt eq 'SQL_DECIMAL'
	) {
		my $len = $fld->size();
		if ($len =~ /24,[24]/) # Note versions of currency
		{
			$dt = 'currency';
		}
		else
		{
			die('Unknown SQL Type');
		}
	}
	elsif (
		$dt eq 'SQL_TIMESTAMP' ||
		$dt eq 'SQL_DATE'
	) {
		if ($dt eq 'SQL_DATE')
		{
			my $alt = $fld->data_type();
			if ($alt =~ /^date$/)
			{
				$dt = 'date';
			}
			elsif ($alt =~ /^datetime$/)
			{
				$dt = 'datetime';
			}
		}
		elsif ($dt eq 'SQL_TIMESTAMP')
		{
			$dt = 'datetime';
			if (reftype($def) eq 'SCALAR')
			{
				if ($$def eq 'CURRENT_TIMESTAMP')
				{
					$def = undef;
					$res->{'timestamp'} = 1;
				}
			}
		}
		if ($def eq 'NULL')
		{
			$def = undef;
		}
	}
	else
	{
		die('Unknown SQL Type: '. $dt);
	}
	if (defined $def)
	{
		$res->{'default'} = $def;
	}
	elsif ($res->{'null'})
	{
		$res->{'default_null'} = 1;
	}
	$res->{'name'} = $fld->name();
	$res->{'type'} = $dt;
	return $res;
}

1;
