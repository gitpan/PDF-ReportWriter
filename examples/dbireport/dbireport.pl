#
# Show an example of access to an external DBI data source
# Cosimo Streppone <cosimo@cpan.org>
# 2006-03-20
#
# $Id: dbireport.pl,v 1.1 2006/03/20 17:22:58 cosimo Exp $

use strict;
use PDF::ReportWriter;

my $rw = PDF::ReportWriter->new();

# Data comes from `datasource' definition
# in ./dbireport.xml report profile
# 
# Check the `account' csv file or the
# `account.sql' database dump

$rw->render_report('./dbireport.xml');
$rw->save();
