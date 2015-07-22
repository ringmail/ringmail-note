package Note::DBManager;
use strict;
use warnings;

use Moose;
use JSON::XS;
use Data::Dumper;
use SQL::Translator;
use SQL::Translator::Diff;
use SQL::Translator::Parser::MySQL;
use RDF::Trine ('iri', 'statement', 'literal', 'blank');

use Note::Param;
use Note::SQL::Database;
use Note::RDF::Sparql;
use Note::RDF::NS ('ns_iri');
use Note::RDF::Class;

use vars qw(%datatype);

no warnings 'uninitialized';

has 'root' => (
	'is' => 'rw',
	'isa' => 'Str',
	'required' => 1,
);

has 'database' => (
	'is' => 'rw',
	'isa' => 'Note::SQL::Database',
);

our %datatype = (
	'ref' => 1,
	'text' => 1,
	'binary' => 1,
	'boolean' => 1,
	'integer' => 1,
	'float' => 1,
	'currency' => 1,
	'date' => 1,
	'datetime' => 1,
);

sub iterate_dir
{
	my ($obj, $root) = @_;
	$root ||= $obj->root();
	my $dir = undef;
	unless (-d $root)
	{
		die(qq|Invalid database directory: '$root'|);
	}
	unless (opendir($dir, $root))
	{
		die(qq|Unable to open directory '$root': $!|);
	}
	my @items = readdir($dir);
	closedir($dir);
	my @files = ();
	foreach my $f (sort @items)
	{
		next if ($f =~ /^\./);
		next unless ($f =~ /\.njs$/);
		my $path = "$root/$f";
		next if (-d $path);
		$f =~ s/\.njs$//;
		push @files, [$f, $path];
	}
	return \@files;
}

sub table_sql
{
	my ($obj, $name, $data, $schref) = @_;
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
		$schema->add_table($table);
		if (ref($schref))
		{
			$$schref = $schema;
		}
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
		die ('SQL translate error');
	}
	while ($sql =~ s/^(.*?index.*?)\((\d+)\)\`/$1`($2)/im) { 1; }
	my @pts = split /\n\n/, $sql;
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
		my $def = ($fld->{'default'}) ? 1 : 0;
		$field->default_value(\$def);
	}
	elsif (
		($type eq 'text' && ! ($fld->{'length'} =~ /^\d+$/ && $fld->{'length'} <= 255)) ||
		($type eq 'binary' && ! ($fld->{'length'} =~ /^\d+$/ && $fld->{'length'} <= 255))
	) {
		# no default value in MySQL 5.6
	}
	elsif ($fld->{'default_null'})
	{
		$field->default_value(\'NULL');
	}
	elsif (defined ($fld->{'default'}))
	{
		$field->default_value($fld->{'default'});
	}
	return $field->schema();
}

sub json_load
{
	my ($obj, $fp) = @_;
	my $fh = undef;
	unless (open($fh, '<', $fp))
	{
		die(qq|Unable to open file '$fp': $!|);
	}
	local $/;
	$/ = undef;
	my $fdata = <$fh>;
	close($fh);
	my $data = decode_json($fdata);
	return $data;
}

sub json_save
{
	my ($obj, $fp, $data) = @_;
	my $fh = undef;
	unless (open($fh, '>', $fp))
	{
		die(qq|Unable to open file '$fp': $!|);
	}
	print $fh JSON::XS->new()->utf8()->pretty()->canonical()->encode($data);
	close($fh);
	return $data;
}

sub table_parse
{
	my ($obj, $sql) = @_;
	my $trns = new SQL::Translator();
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

sub build_sql_tables
{
	my ($obj) = @_;
	my $tables = $obj->iterate_dir();
	my @res = ();
	my $diffs = '';
	foreach my $t (@$tables)
	{
		my $tdata = $obj->json_load($t->[1]);
		my $tname = $t->[0];
		my $schema;
		my $sql = $obj->table_sql($tname, $tdata, \$schema);
		my $current = $obj->db_show_create($tname);
		if (defined $current) # compare schemas
		{
			my $diff = $obj->table_diff($current, $sql, $tname);
			if (defined $diff)
			{
				print "Updated: $tname\n";
				$diffs .= $diff;
			}
			else
			{
				print "Exists: $tname\n";
			}
			#print "Diff: $diff\n" if (defined $diff);
		}
		else # no table, need to create
		{
			print "Create: $tname\n";
			#$obj->db_create_table($sql);
			$diffs .= $sql. "\n";
		}
		push @res, $sql;
	}
	if (length($diffs))
	{
		print "Diffs:\n$diffs";
	}
	return \@res;
}

sub db_show_create
{
	my ($obj, $table) = @_;
	my $db = $obj->database();
	my $sql = "SHOW CREATE TABLE `$table`";
	my $q;
	eval {
		$q = $db->query($sql);
	};
	if ($@)
	{
		my $err = $@;
		if ($err =~ /DBD::mysql::st execute failed: Table '.*?' doesn't exist/)
		{
			return undef;
		}
		else
		{
			die($@);
		}
	}
	if (scalar (@$q))
	{
		return $q->[0]->[1];
	}
	return undef;
}

sub db_create_table
{
	my ($obj, $sql) = @_;
	my $db = $obj->database();
	eval {
		$db->do($sql);
	};
	if ($@)
	{
		die("SQL Create Table Failed For:\n$sql\nDBI Error: $@");
	}
}

sub build_sql_links
{
	my ($obj) = @_;
	my $tables = $obj->iterate_dir();
	my %tlinks = ();
	foreach my $t (@$tables)
	{
		my $tdata = $obj->json_load($t->[1]);
		my $tname = $t->[0];
		foreach my $k (sort keys %{$tdata->{'columns'}})
		{
			my $coldata = $tdata->{'columns'}->{$k};
			if ($coldata->{'type'} eq 'record')
			{
				my $ft = $coldata->{'table'};
				my $info = '';
				if ($coldata->{'parent'})
				{
					$info .= ' Parent';
					$tlinks{$tname} ||= {};
					$tlinks{$tname}->{'parent'} = $coldata->{'table'};
					$tlinks{$tname}->{'parent_field'} = $k;
					if (defined $coldata->{'max_cardinality'})
					{
						$tlinks{$tname}->{'cardinality'} = $coldata->{'max_cardinality'};
					}
					$tlinks{$coldata->{'table'}} ||= {};
					$tlinks{$coldata->{'table'}}->{'next'}->{$tname} = 1;
				}
				if ($coldata->{'max_cardinality'} == 1)
				{
					$info .= ' 1:1';
				}
				#print "$tname.$k => $ft.id$info\n";
				#print Dumper($coldata);
			}
		}
		#print "$tname ". Dumper($tdata);
	}
	my $pariter;
	$pariter = sub {
		my ($par, $phash, $ptable) = @_;
		if (exists $phash->{$ptable})
		{
			die(qq|Cycle in table heirarchy at table: '$ptable'|);
		}
		push @$par, $ptable;
		$phash->{$ptable} = $ptable;
		my $ntd = $tlinks{$ptable};
		if ($ntd->{'parent'})
		{
			$pariter->($par, $phash, $ntd->{'parent'});
		}
	};
	foreach my $k (sort keys %tlinks)
	{
		my $td = $tlinks{$k};
		if ($td->{'parent'})
		{
			my @par = ();
			my %phash = ();
			$pariter->(\@par, \%phash, $td->{'parent'});
			#$td->{'parents'} = \@par;
		}
	}
	#print Dumper(\%tlinks);
	return \%tlinks;
}

sub to_rdf
{
	my ($obj, $param) = get_param(@_);
	my $name = $param->{'name'};
	my $data = $param->{'data'};
	my $rdf = $param->{'rdf'};
	my $base = $param->{'base_uri'};
	my $model = iri($base. $name);
	my $class = Note::RDF::Class::create(
		'rdf' => $rdf,
		'id' => $model,
	);
	$rdf->add_statement($model, ns_iri('rdf', 'type'), ns_iri('note', 'class/data/model'));
	foreach my $k (sort keys %{$data->{'columns'}})
	{
		my $cv = $data->{'columns'}->{$k};
		my $type = $cv->{'type'};
		$type = 'ref' if ($type eq 'record');
		if ($datatype{$type})
		{
			my $col = iri($base. $name. '/'. $k);
			my $prop = $class->add_property(
				'id' => $col,
			);
			$rdf->add_statement($col, ns_iri('rdf', 'type'), ns_iri('note', 'class/data/field'));
			$rdf->add_statement($model, ns_iri('note', 'attr/data/model/field'), $col);
			$rdf->add_statement($col, ns_iri('note', 'attr/data/field/key'), literal($k));
			$rdf->add_statement($col, ns_iri('note', 'attr/data/field/type'), ns_iri('note', 'inst/data/type/'. $type));
			my $dt = undef;
			if ($type eq 'ref')
			{
				if (defined $cv->{'class'}) # any URI
				{
					$dt = iri($cv->{'class'});
					$rdf->add_statement($col, ns_iri('note', 'attr/data/field/class'), $dt);
				}
				elsif (defined $cv->{'table'}) # model URI
				{
					$dt = iri($base. $cv->{'table'});
					$rdf->add_statement($col, ns_iri('note', 'attr/data/field/table'), $dt);
				}
			}
			if (defined $dt)
			{
				$prop->add_range(
					'class' => $dt,
				);
			}
			if (defined $cv->{'null'})
			{
				$rdf->add_statement($col, ns_iri('note', 'attr/data/field/null'), literal($cv->{'null'}));
			}
			if (defined $cv->{'default'})
			{
				$rdf->add_statement($col, ns_iri('note', 'attr/data/field/default'), literal($cv->{'default'}));
			}
			if (defined $cv->{'default_null'})
			{
				$rdf->add_statement($col, ns_iri('note', 'attr/data/field/default_null'), literal($cv->{'default_null'}));
			}
			if (defined $cv->{'timestamp'})
			{
				$rdf->add_statement($col, ns_iri('note', 'attr/data/field/timestamp'), literal($cv->{'timestamp'}));
			}
			if (defined $cv->{'length'})
			{
				$rdf->add_statement($col, ns_iri('note', 'attr/data/field/length'), literal($cv->{'length'}));
				if ($cv->{'length'} eq 'specify')
				{
					if (defined $cv->{'length_specify'})
					{
						$rdf->add_statement($col, ns_iri('note', 'attr/data/field/length_specify'), literal($cv->{'length_specify'}));
					}
				}
			}
		}
	}
}

sub from_rdf
{
	my ($obj, $param) = get_param(@_);
	my $id = $param->{'id'};
	my $rdf = $param->{'rdf'};
	my $base = $param->{'base_uri'};
	my $model_type = $rdf->get_statements(
		$id, ns_iri('rdf', 'type'), ns_iri('note', 'class/data/model'),
	);
	unless ($model_type->next())
	{
		die(q|Model not found: '|. $id->uri_value(). q|'|);
	}
	my $prop_iter = $rdf->get_statements(
		$id, ns_iri('note', 'attr/data/model/field'), undef,
	);
	my $data = {};
	while (my $p = $prop_iter->next())
	{
		my $prop = $p->[2];
		my $prec = {};
		my $prop_id = undef;
		my %prop_data = (
			'note:attr/data/field/key' => sub {
				my ($s, $p, $v) = @_;
				$prec->{'name'} = $v->literal_value();
			},
			'note:attr/data/field/type' => sub {
				my ($s, $p, $v) = @_;
				my $tv = $v->uri_value();
				my $type_base = ns_iri('note', 'inst/data/type/')->uri_value();
				$type_base = quotemeta($type_base);
				if ($tv =~ s/^$type_base//)
				{
					$tv = 'record' if ($tv eq 'ref');
					$prec->{'type'} = $tv;
				}
			},
			'attr/data/field/class' => sub {
				my ($s, $p, $v) = @_;
				$prec->{'class'} = $v->uri_value();
			},
			'attr/data/field/table' => sub {
				my ($s, $p, $v) = @_;
				my $cv = $v->uri_value();
				my $table_base = quotemeta($base);
				if ($cv =~ s/^$table_base//)
				{
					$prec->{'table'} = $cv;
				}
			},
			'attr/data/field/null' => sub {
				my ($s, $p, $v) = @_;
				$prec->{'null'} = $v->literal_value();
			},
			'attr/data/field/default' => sub {
				my ($s, $p, $v) = @_;
				$prec->{'default'} = $v->literal_value();
			},
			'attr/data/field/default_null' => sub {
				my ($s, $p, $v) = @_;
				$prec->{'default'} = $v->literal_value();
			},
			'attr/data/field/length' => sub {
				my ($s, $p, $v) = @_;
				$prec->{'length'} = $v->literal_value();
			},
			'attr/data/field/length_specify' => sub {
				my ($s, $p, $v) = @_;
				$prec->{'length'} = $v->literal_value();
			},
			'attr/data/field/default' => sub {
				my ($s, $p, $v) = @_;
				$prec->{'default'} = $v->literal_value();
			},
			'attr/data/field/default_null' => sub {
				my ($s, $p, $v) = @_;
				$prec->{'default_null'} = $v->literal_value();
			},
			'attr/data/field/timestamp' => sub {
				my ($s, $p, $v) = @_;
				$prec->{'timestamp'} = $v->literal_value();
			},
		);
	}
}

1;

