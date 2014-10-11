package Note::RDF::NS;
use strict;
use warnings;
no warnings qw(uninitialized);

BEGIN: {
	use RDF::Trine ('iri');
	use vars qw(@ISA @EXPORT_OK %xmlns %xmlns_reverse @xmlregex @xmlregex_ns @xmlregex_uri);
	require Exporter;
	@ISA = qw(Exporter);
	@EXPORT_OK = qw(ns_uri ns_iri rdf_ns rdf_prefix ns_match);
	our %xmlns = (
		'atx' => 'http://schema.atellix.com/v1/',
		'data' => 'http://data.atellix.com/v1/',
		'bibo' => 'http://purl.org/ontology/bibo/',
		'bio' => 'http://purl.org/vocab/bio/0.1/',
		'cc' => 'http://creativecommons.org/ns#',
		'dc' => 'http://purl.org/dc/elements/1.1/',
		'dct' => 'http://purl.org/dc/terms/',
		'doap' => 'http://usefulinc.com/ns/doap#',
		'foaf' => 'http://xmlns.com/foaf/0.1/',
		'frbr' => 'http://purl.org/vocab/frbr/core#',
		'geo' => 'http://www.w3.org/2003/01/geo/wgs84_pos#',
		'gr' => 'http://purl.org/goodrelations/v1#',
		'gn' => 'http://www.geonames.org/ontology#',
		'ical' => 'http://www.w3.org/2002/12/cal/ical#',
		'og' => 'http://ogp.me/ns#',
		'org' => 'http://www.w3.org/ns/org#',
		'owl' => 'http://www.w3.org/2002/07/owl#',
		'rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
		'rdfa' => 'http://www.w3.org/ns/rdfa#',
		'rdfg' => 'http://www.w3.org/2004/03/trix/rdfg-1/',
		'rdfs' => 'http://www.w3.org/2000/01/rdf-schema#',
		'rev' => 'http://purl.org/stuff/rev#',
		'rss' => 'http://purl.org/rss/1.0/',
		'sioc' => 'http://rdfs.org/sioc/ns#',
		'skos' => 'http://www.w3.org/2004/02/skos/core#',
		'vann' => 'http://purl.org/vocab/vann/',
		'vcard' => 'http://www.w3.org/2006/vcard/ns#',
		'void' => 'http://rdfs.org/ns/void#',
		'wdrs' => 'http://www.w3.org/2007/05/powder-s#',
		'wot' => 'http://xmlns.com/wot/0.1/',
		'xhv' => 'http://www.w3.org/1999/xhtml/vocab#',
		'xsd' => 'http://www.w3.org/2001/XMLSchema#',
	);
	setup_ns();
};

sub setup_ns
{
	our %xmlns_reverse = reverse %xmlns;
	our @xmlregex = ();
	our @xmlregex_ns = ();
	our @xmlregex_uri = ();
	foreach my $k (sort keys %xmlns)
	{
		my $uri = $xmlns{$k};
		my $qm = quotemeta($uri);
		my $re = qr/^$qm/;
		push @xmlregex, $re;
		push @xmlregex_ns, $k;
		push @xmlregex_uri, $uri;
	}
}

sub ns_match
{
	my ($uri, $pathref) = @_;
	foreach my $i (0..$#xmlregex)
	{
		my $re = $xmlregex[$i];
		if ($uri =~ /$re(.*$)/)
		{
			my $path = $1;
			if (ref($pathref) && $pathref =~ /SCALAR/)
			{
				$$pathref = $path;
			}
			return $xmlregex_ns[$i];
		}
	}
	return undef;
}

sub rdf_ns
{
	my ($ns) = @_;
	return $xmlns{$ns};
}

sub ns_uri
{
	my ($ns, $path) = @_;
	return rdf_ns($ns). $path;
}

sub ns_iri
{
	return iri(ns_uri(@_));
}

sub rdf_prefix
{
	my $lines = '';
	if (ref($_[0]) && $_[0] =~ /ARRAY/)
	{
		foreach my $i (@{$_[0]})
		{
			$lines .= rdf_prefix_line($i);
		}
	}
	else
	{
		foreach my $i (@_)
		{
			$lines .= rdf_prefix_line($i);
		}
	}
	return $lines;
}

sub rdf_prefix_line
{
	my ($ns) = @_;
	if (defined $xmlns{$ns})
	{
		my $uri = $xmlns{$ns};
		my $line = "PREFIX $ns: <$uri>\n";
		return $line;
	}
	return undef;
}

1;
