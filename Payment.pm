package Note::Payment;
use strict;
use warnings;

use Data::Dumper;
use Business::PayPal::API qw(DirectPayments);
use POSIX 'strftime';
use Business::CCCheck qw(@CC_months CC_year CC_expired CC_is_zip CC_is_name CC_is_addr CC_clean CC_digits CC_format);
use Business::OnlinePayment;
use Storable 'nfreeze', 'thaw';
use Number::Format 'format_number';
use URI::Escape 'uri_escape';

use Note::Row;
use Note::Account qw(account_id transaction tx_type_id);
use Note::SQL::Table 'sqltable';
use Note::Param;

# static method
sub dofork
{
	my ($nofork) = @_;
	unless ($nofork)
	{
		$SIG{'CHLD'} = 'IGNORE';
		my $ofh = select(STDOUT);
		$| = 1;
		select $ofh;
		my $kpid = fork();
		if ($kpid)
		{
			waitpid($kpid, 0);
			return 0;
		}
		else
		{
			close STDIN;
			close STDOUT;
			close STDERR;
			unless (fork())
			{
				open STDIN, '</dev/null' or die("Open: $!");
				open STDOUT, '>/dev/null' or die("Open: $!");
				open STDERR, '>/dev/null' or die("Open: $!");
				return 1;
			}
			else
			{
				CORE::exit(0);
			}
		}
	}
	else
	{
		return 1;
	}
}

# static method
sub doexit
{
	my ($nofork) = @_;
	unless ($nofork)
	{
		CORE::exit(0);
	}
}

# id is user_id
sub new
{
	my $class = shift;
	my $id = shift;
	my $rc = new Note::Row('ring_user' => {'id' => $id});
	unless (defined $rc->id())
	{
		die(qq|Invalid user: '$id'|);
	}
	my $obj = {
		'id' => $rc->id(),
	};
	bless $obj, $class;
	return $obj;
}

sub card_list
{
	my ($obj, $deleted) = @_;
	$deleted = ($deleted) ? 1 : 0;
	my $q = sqltable('payment_card')->get(
		'array' => 1,
		'select' => 'id',
		'where' => {
			'user_id' => $obj->{'id'},
			'deleted' => $deleted,
		},
		'order' => 'id desc',
	);
	return [map {$_->[0]} @$q];
}

sub card_check
{
	my ($obj, $param) = get_param(@_);
	my $err = '';
	my $type = CC_digits($param->{'num'});
	my $intype = $param->{'type'};
	if ($intype eq 'AMEX')
	{
		$intype = 'AmericanExpress';
	}
	if (lc($type) eq lc($intype))
	{
		if (CC_expired($param->{'expm'}, $param->{'expy'}))
		{
			$err = 'Expired card';
		}
		else
		{
			return 1;
		}
	}
	else
	{
		$err = 'Invalid card number';
	}
	if (ref($param->{'error'}) && $param->{'error'} =~ /SCALAR/)
	{
		${$param->{'error'}} = $err;
	}
	return 0;
}

sub card_add
{
	my ($obj, $param) = get_param(@_);
	my $err = '';
	unless ($obj->card_check(
		'num' => $param->{'num'},
		'type' => $param->{'type'},
		'expy' => $param->{'expy'},
		'expm' => $param->{'expm'},
		'error' => \$err,
	)) {
		die($err);
	}
	$param->{'num'} =~ /(.{6})$/;
	my $post = $1;
	my $rec = {
		'cc_post' => $post,
		'use_contact' => ($param->{'use_contact'}) ? 1 : 0,
		'deleted' => 0,
	};
	my @ccflds = (qw/type expy expm/);
	foreach my $k (@ccflds)
	{
		$rec->{'cc_'. $k} = $param->{$k};
	}
	my @flds = (qw/first_name last_name address address2 city state zip/);
	foreach my $k (@flds)
	{
		if ($param->{'use_contact'})
		{
			$rec->{$k} = undef;
		}
		else
		{
			$rec->{$k} = $param->{$k};
		}
	}
	my $q = sqltable('payment_card')->get(
		'array' => 1,
		'select' => 'id',
		'where' => {
			'user_id' => $obj->{'id'},
			'cc_type' => $rec->{'cc_type'},
			'cc_post' => $rec->{'cc_post'},
		},
	);
	my $data = {
		'cc_num' => $param->{'num'},
		'cc_cvv2' => $param->{'cvv2'},
	};
	$rec->{'data'} = nfreeze($data);
	if (scalar @$q)
	{
		my $rc = new Note::Row('payment_card' => $q->[0]->[0]);
		$rec->{'deleted'} = 0;
		$rc->update($rec);
		return $rc->{'id'};
	}
	else
	{
		$rec->{'user_id'} = $obj->{'id'};
		my $rc = Note::Row::create('payment_card', $rec);
		return $rc->{'id'};
	}
}

sub card_update_exp
{
	my ($obj, $card_id, $exp_month, $exp_year) = @_;
	my $crd = new Note::Row('payment_card' => $card_id);
	$crd->update({'cc_expm' => $exp_month, 'cc_expy' => $exp_year,});
}

sub card_delete
{
	my ($obj, $cardid) = @_;
	my $crd = new Note::Row('payment_card' => $cardid);
	$crd->update({'deleted' => 1});
}

sub card_view
{
	my ($obj, $cardid) = @_;
	my $crd = new Note::Row('payment_card' => $cardid);
	return $crd->data('cc_type', 'cc_post', 'cc_expm', 'cc_expy');
}

sub card_data
{
	my ($obj, $cardid) = @_;
	my $crd = new Note::Row('payment_card' => $cardid);
	my $rec = $crd->data('cc_type', 'cc_expm', 'cc_expy', 'data');
	$rec->{'data'} = thaw($rec->{'data'});
	$rec->{'cc_cvv2'} = $rec->{'data'}->{'cc_cvv2'};
	$rec->{'cc_num'} = $rec->{'data'}->{'cc_num'};
	delete $rec->{'data'};
	return $rec;
}

sub card_contact
{
	my ($obj, $cardid) = @_;
	my $rec = new Note::Row('payment_card' => $cardid);
	my $ct;
	if ($rec->data('use_contact'))
	{
		# TODO
	}
	else
	{
		my @flds = (qw/first_name last_name address address2 city state zip/);
		$ct = $rec->data(@flds);
	}
	return $ct;
}

sub card_payment
{
	my ($obj, $param) = get_param(@_);
	my $cid = $param->{'card_id'};
	my $cd = $obj->card_data($cid);
	my $ct = $obj->card_contact($cid);
	my $proc = $param->{'processor'};
	if ($proc =~ /^paypal$/i)
	{
		return $obj->payment_paypal(
			'callback' => $param->{'callback'},
			'nofork' => $param->{'nofork'},
			'amount' => $param->{'amount'},
			'card_id' => $cid,
			'ip' => $param->{'ip'},
			%$cd,
			%$ct,
		);
	}
#	elsif ($proc =~ /^authorizenet$/i)
#	{
#		return payment_authorizenet(
#			'callback' => $param->{'callback'},
#			'nofork' => $param->{'nofork'},
#			'amount' => $param->{'amount'},
#			'card_id' => $cid,
#			'acct_dst' => $param->{'account'},
#			'operator' => $param->{'operator'},
#			'ip' => $param->{'ip'},
#			%$cd,
#			%$ct,
#		);
#	}
}

# static method
sub proc_id
{
	my ($name) = @_;
	my $r = Note::Row::find_create('payment_proc' => {
		'name' => $name,
	});
	return $r->id();
}

sub payment_paypal
{
	my ($obj, $param) = get_param(@_);
	my $pid = proc_id('paypal');
	my $src = account_id('payment_paypal');
	my $dst = new Note::Account($obj->{'id'});
	my $amount = $param->{'amount'};
	my $cfg = $main::note_config->config();
	$param->{'cc_type'} = 'Amex' if ($param->{'cc_type'} eq 'AMEX');
	my $lock;
	eval {
		$lock = Note::Row::create('payment_lock', {
			'account' => $dst->{'id'},
		});
	};
	if ($@) # Transaction in progress
	{
		return undef;
	}
	my $attempt = Note::Row::create('payment_attempt', {
		'amount' => $param->{'amount'},
		'ts' => strftime("%F %T", localtime(time())),
		'accepted' => 0,
		'card_id' => $param->{'card_id'},
		'proc_id' => $pid,
		'account' => $dst->{'id'},
		'user_id' => $obj->{'id'},
		'result' => 'processing',
	});
	$lock->update({
		'attempt' => $attempt->{'id'},
	});
	if (dofork($param->{'nofork'}))
	{
		my $pp = new Business::PayPal::API(
			'Username' => $cfg->{'paypal_user'},
			'Password' => $cfg->{'paypal_password'},
			'Signature' => $cfg->{'paypal_signature'},
			'sandbox' => ($cfg->{'paypal_sandbox'}) ? 1 : 0,
		);
#		::log({
#			'PaymentAction' => 'Sale',
#			'OrderTotal' => $param->{'amount'},
#			'CreditCardType' => $param->{'cc_type'},
#			'CreditCardNumber' => $param->{'cc_num'},
#			'ExpMonth' => $param->{'cc_expm'},
#			'ExpYear' => $param->{'cc_expy'},
#			'CVV2' => $param->{'cc_cvv2'},
#			'FirstName' => $param->{'first_name'},
#			'LastName' => $param->{'last_name'},
#			'Street1' => $param->{'address'},
#			'Street2' => $param->{'address2'},
#			'CityName' => $param->{'city'},
#			'StateOrProvince' => $param->{'state'},
#			'PostalCode' => $param->{'zip'},
#			'Country' => 'US',
#			'CurrencyID' => 'USD',
#			'IPAddress' => $param->{'ip'},
#		});
		my %resp;
		eval {
			%resp = $pp->DoDirectPaymentRequest(
				'PaymentAction' => 'Sale',
				'OrderTotal' => $param->{'amount'},
				'CreditCardType' => $param->{'cc_type'},
				'CreditCardNumber' => $param->{'cc_num'},
				'ExpMonth' => $param->{'cc_expm'},
				'ExpYear' => $param->{'cc_expy'},
				'CVV2' => $param->{'cc_cvv2'},
				'FirstName' => $param->{'first_name'},
				'LastName' => $param->{'last_name'},
				'Street1' => $param->{'address'},
				'Street2' => $param->{'address2'},
				'CityName' => $param->{'city'},
				'StateOrProvince' => $param->{'state'},
				'PostalCode' => $param->{'zip'},
				'Country' => 'US',
				'CurrencyID' => 'USD',
				'IPAddress' => $param->{'ip'},
				#MerchantSessionID => '10113301', # TODO
			);
		};
		if ($@)
		{
			my $err = Note::Row::create('payment_error', {
				'error_summary' => 'timeout',
				'error_data' => nfreeze({
					'error' => $@,
				}),
				'error_text' => 'There was a problem connecting to our payment processor. Please try again in a few minutes.',
			});
			$attempt->update({
				'error' => $err->{'id'},
				'result' => 'error',
			});
		}
		else
		{
			if ($resp{'Ack'} =~ /success/i)
			{
				my $prec = Note::Row::create('payment', {
					'amount' => $param->{'amount'},
					'ts' => strftime("%F %T", localtime(time())),
					'card_id' => $param->{'card_id'},
					'proc_id' => $pid,
					'ref_id' => $resp{'TransactionID'} || '?',
					'ref_id_2' => $resp{'CorrelationID'} || '?',
					'user_id' => $obj->{'id'},
					'account' => $dst->{'id'},
				});
				$attempt->update({
					'accepted' => 1,
					'result' => 'accepted',
					'payment' => $prec->{'id'},
				});
				transaction(
					'acct_src' => $src,
					'acct_dst' => $dst,
					'amount' => $param->{'amount'},
					'entity' => $prec->{'id'},
					'tx_type' => tx_type_id('payment_cc'),
					'user_id' => $obj->{'id'},
				);
				if (defined $param->{'callback'})
				{
					if (ref($param->{'callback'}) eq 'CODE')
					{
						$param->{'callback'}->();
					}
				}
			}
			else
			{
				my $errors = $resp{'Errors'};
				my $errdata = {
					'LongMessage' => 'Unrecognized error received from payment processor.',
				};
				my $es = 'error';
				my %errcode = (
					'10002' => 'login',
					'10504' => 'bad_cvv2',
					'10502' => 'expired',
					'10759' => 'bad_card',
					'10761' => 'duplicate',
					'10762' => 'bad_cvv2',
					'10764' => 'declined',
					'15001' => 'declined',
					'15002' => 'declined',
					'15004' => 'bad_cvv2',
					'15006' => 'bad_card',
					'15007' => 'expired',
					'11611' => 'fraud',
				);
				if (ref($errors) && $errors =~ /ARRAY/)
				{
					$errdata = $errors->[0];
				}
				if (exists $errcode{$errdata->{'ErrorCode'}})
				{
					$es = $errcode{$errdata->{'ErrorCode'}};
				}
				my $et = $errdata->{'LongMessage'};
				my $err = Note::Row::create('payment_error', {
					'error_summary' => $es,
					'error_data' => nfreeze(\%resp),
					'error_text' => $et,
				});
				$attempt->update({
					'error' => $err->{'id'},
					'result' => 'error',
				});
				::log("PayPal Error: ", \%resp);
			}
		}
		$lock->delete();
		doexit($param->{'nofork'});
	}
	return $attempt->{'id'};
}

1;

