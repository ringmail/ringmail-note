package Note::RDF::Sparql;
use strict;
use warnings;
no warnings 'uninitialized';

use vars qw();

use Moose;
use Data::Dumper;
use RDF::Trine ('iri', 'statement', 'literal');
use RDF::Trine::Node;
use RDF::Trine::Store;
use RDF::Query;
use RDF::Query::Client;
use Scalar::Util ('blessed', 'reftype');

use Note::Param;
use Note::RDF::NS ('ns_iri', 'rdf_ns');

no warnings qw(uninitialized);

has 'context' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Node',
	'lazy' => 1,
	'default' => sub {
		return new RDF::Trine::Node::Nil();
	},
);

has 'endpoint' => (
	'is' => 'rw',
	'isa' => 'Str',
);

has 'model' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Model',
	'lazy' => 1,
	'default' => sub {
		my ($obj) = @_;
		return new RDF::Trine::Model($obj->storage());
	},
);

has 'storage' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Store',
	'lazy' => 1,
	'default' => sub {
		my ($obj) = @_;
		my $endp = $obj->endpoint();
		if (defined $endp)
		{
			my $store = new RDF::Trine::Store::SPARQL($endp);
			$store->{'ua'}->default_header('Accept' => 'application/sparql-results+xml;q=0.9,application/rdf+xml');
			return $store;
		}
		else
		{
			return new RDF::Trine::Store::Memory();
		}
	},
);

sub get_resource
{
	my ($obj, $rsrc) = @_;
	my $ctxt = $obj->context();
	my $sto = $obj->storage();
	my $propiter = $sto->get_statements(
		$rsrc,
		undef,
		undef,
		$ctxt,
	);
	my $model = new RDF::Trine::Model();
	$model->add_iterator($propiter);
	return $model;
}

sub add_statement
{
	my ($obj, $stmt) = @_;
	unless (blessed($stmt) && $stmt->isa('RDF::Trine::Statement'))
	{
		die(qq|Invalid statement: '$stmt'|);
	}
	$obj->insert('statement' => $stmt);
}

sub query
{
	my ($obj, $param) = get_param(@_);
	my $endp = $obj->endpoint();
	my $iter = undef;
	if (defined $endp)
	{
		my $cli = new RDF::Query::Client($param->{'sparql'});
		$iter = $cli->execute($endp);
		unless (defined $iter)
		{
			die('RDF Query Error: '. $cli->error());
		}
	}
	else
	{
		my $qry = new RDF::Query($param->{'sparql'});
		#print $obj->model()->as_string();
		$iter = $qry->execute($obj->model());
		unless (defined $iter)
		{
			die('RDF Query Error: '. $qry->error());
		}
	}
	return $iter;
}

sub insert
{
	my ($obj, $param) = get_param(@_);
	my $store = $obj->storage();
	my $stmt;
	if (defined $param->{'statement'})
	{
		$stmt = $param->{'statement'};
	}
	else
	{
		$stmt = statement($param->{'subject'}, $param->{'predicate'}, $param->{'object'});
	}
	my $ctxt = $obj->context();
	my $endp = $obj->endpoint();
	if (defined $endp)
	{
		my $sparql = 'INSERT IN GRAPH '. $ctxt->as_ntriples(). ' { ';
		$sparql .= join(' ', map { $_->as_ntriples() } $stmt->nodes()). '.';
		$sparql .= ' }';
		my $resp = $store->{'ua'}->post($store->{'url'}, {'query' => $sparql});
		#print "SPARQL Insert Reply: ". $resp->status_line(). "\n". $resp->content();
		unless ($resp->is_success())
		{
			die("SPARQL Insert Reply: ". $resp->status_line(). "\n". $resp->content());
		}
	}
	else
	{
		#$store->add_statement($stmt, $ctxt);
		$store->add_statement($stmt);
	}
}

sub delete
{
	my ($obj, $param) = get_param(@_);
	my $store = $obj->storage();
	my $stmt;
	if (defined $param->{'statement'})
	{
		$stmt = $param->{'statement'};
	}
	else
	{
		$stmt = statement($param->{'subject'}, $param->{'predicate'}, $param->{'object'});
	}
	my $ctxt = $obj->context();
	my $endp = $obj->endpoint();
	if (defined $endp)
	{
		my $sparql = 'DELETE FROM GRAPH '. $ctxt->as_ntriples(). ' { ';
		$sparql .= join(' ', map { $_->as_ntriples() } $stmt->nodes());
		$sparql .= ' }';
		my $resp = $store->{'ua'}->post($store->{'url'}, {'query' => $sparql});
		#print "SPARQL Delete Reply: ". $resp->status_line(). "\n". $resp->content();
		unless ($resp->is_success())
		{
			die("SPARQL Delete Reply: ". $resp->status_line(). "\n". $resp->content());
		}
	}
	else
	{
		$store->remove_statement($stmt, $ctxt);
	}
}

sub get_statements
{
	my ($obj, $subj, $pred, $val) = @_;
	return $obj->storage()->get_statements($subj, $pred, $val, $obj->context());
}

sub build_sparql
{
	my ($obj, $param) = get_param(@_);
	my $sparql = '';
	my %ks = ();
	my %prefix = ();
	if (exists($param->{'prefix'}) && reftype($param->{'prefix'}) eq 'HASH')
	{
		%prefix = %{$param->{'prefix'}};
	}
	my @where = ();
	if (exists($param->{'where'}))
	{
		if (reftype($param->{'where'}) eq 'ARRAY')
		{
			foreach my $wh (@{$param->{'where'}})
			{
				unless (reftype($wh) eq 'ARRAY')
				{
					die(qq|Invalid where clause: '$wh'|);
				}
				if (! ref($wh->[0]))
				{
					if ($wh->[0] =~ /^\?/)
					{
						$ks{$wh->[0]} = 1;
					}
					elsif ($wh->[0] =~ /^(\w+)\:$/)
					{
						$prefix{$1} ||= rdf_ns($1);
					}
				}
				else
				{
					$wh->[0] = $wh->[0]->as_ntriples();
				}
				if (! ref($wh->[1]))
				{
					if ($wh->[1] =~ /^\?/)
					{
						$ks{$wh->[1]} = 1;
					}
					elsif ($wh->[1] =~ /^(\w+)\:/)
					{
						$prefix{$1} ||= rdf_ns($1);
					}
				}
				else
				{
					$wh->[1] = $wh->[1]->as_ntriples();
				}
				if (! ref($wh->[2]))
				{
					if ($wh->[2] =~ /^\?/)
					{
						$ks{$wh->[2]} = 1;
					}
					elsif ($wh->[2] =~ /^(\w+)\:/)
					{
						$prefix{$1} ||= rdf_ns($1);
					}
				}
				elsif (! blessed($wh->[2]))
				{
					if (reftype($wh->[2]) eq 'SCALAR')
					{
						$wh->[2] = literal(${$wh->[2]}, undef, ns_iri('xsd', 'string'))->as_ntriples();
					}
					elsif (reftype($wh->[2]) eq 'ARRAY')
					{
						my $ty = $wh->[2]->[1];
						if (blessed($ty) && $ty->isa('RDF::Trine::Node::Resource'))
						{
							$wh->[2] = literal($wh->[2]->[0], undef, $ty)->as_ntriples();
						}
						else
						{
							$ty =~ /^(\w+)\:(.*)$/;
							$prefix{$1} ||= rdf_ns($1);
							$wh->[2] = literal($wh->[2]->[0], undef, ns_iri($1, $2))->as_ntriples();
						}
					}
				}
				else
				{
					$wh->[2] = $wh->[2]->as_ntriples();
				}
				push @where, join(' ', @$wh). '.';
			}
		}
	}
	#print STDERR Dumper(\%prefix);
	foreach my $k (sort keys %prefix)
	{
		my $pval = $prefix{$k};
		if (length($pval))
		{
			$sparql .= "PREFIX $k: <$pval>\n";
		}
	}
	$sparql .= 'SELECT ';
	if ($param->{'distinct'})
	{
		$sparql .= 'DISTINCT ';
	}
	if (defined($param->{'select'}) && reftype($param->{'select'}) eq 'ARRAY')
	{
		$sparql .= join(' ', @{$param->{'select'}});
	}
	else
	{
		$sparql .= join(' ', sort keys %ks);
	}
	$sparql .= "\n";
	if (defined $param->{'from'})
	{
		unless ($param->{'from'} eq '0')
		{
			$sparql .= 'FROM ';
			$sparql .= $obj->context()->as_ntriples();
			$sparql .= "\n";
		}
	}
	else
	{
		$sparql .= 'FROM ';
		$sparql .= $obj->context()->as_ntriples();
		$sparql .= "\n";
	}
	if (scalar @where)
	{
		$sparql .= "WHERE {\n";
		$sparql .= join("\n", map {"\t$_"} @where). "\n";
		if (exists $param->{'filter'})
		{
			my $flt = $param->{'filter'};
			if (ref($flt))
			{
				$flt = $obj->_sparql_filter($flt);
			}
			if (defined $flt)
			{
				$sparql .= "FILTER $flt";
			}
		}
		$sparql .= "}\n";
	}
	if ($param->{'order'})
	{
		$sparql .= "ORDER BY $param->{'order'}\n";
	}
	if ($param->{'limit'})
	{
		$sparql .= "LIMIT $param->{'limit'}\n";
	}
	print STDERR ("SPARQL:\n$sparql") if ($param->{'debug'});
	unless ($param->{'query'} eq '0')
	{
		return $obj->query('sparql' => $sparql);
	}
	return $sparql;
}

sub _sparql_filter
{
	my ($obj, $flt) = @_;
	if (reftype($flt) eq 'ARRAY')
	{
		my @pts = ();
		foreach my $r (@$flt)
		{
			if (ref($r))
			{
				push @pts, $obj->_sparql_filter($r);
			}
			else
			{
				push @pts, $r;
			}
		}
		return '('. join(' ', @pts). ')';
	}
	elsif (reftype($flt) eq 'HASH')
	{
		my @pts = ();
		my @ks = sort keys %$flt;
		foreach my $k (@ks)
		{
			my $r = $flt->{$k};
			if (ref($r))
			{
				if (blessed($r) && $r->isa('RDF::Trine::Node'))
				{
					if ($r->is_literal() || $r->is_resource())
					{
						push @pts, $k. ' = '. $r->as_ntriples();
					}
				}
			}
		}
		unless (scalar @pts)
		{
			return undef;
		}
		return '('. join(' && ', @pts). ')';
	}
}

sub get_rdf_list
{
	my ($obj, $param) = get_param(@_);
	my $list = $param->{'list'};
	my @res = ();
	my $getitem;
	$getitem = sub {
		my ($ls) = @_;
		my $i = $obj->build_sparql(
			'select' => ['?first', '?rest'],
			'where' => [
				[$ls, ns_iri('rdf', 'first'), '?first'],
				[$ls, ns_iri('rdf', 'rest'), '?rest'],
			],
		);
		my $r = $i->next();
		if (defined $r)
		{
			return $r;
		}
		return undef;
	};
	while (my $i = $getitem->($list))
	{
		push @res, $i->{'first'};
		if ($i->{'rest'}->is_nil())
		{
			last;
		}
		$list = $i->{'rest'};
	}
	return \@res;
}

1;

