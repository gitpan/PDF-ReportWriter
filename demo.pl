#!/usr/bin/perl

# Demo app for PDF::ReportWriter

# Please note that while the data in this report it completely feasible, it has not been
# verified, and should be considered an "artist's impression" of the
# revenue of the pinacle of the free world's democratic structure

use strict;

use PDF::ReportWriter;

use constant mm		=> 72/25.4;		# 25.4 mm in an inch, 72 points in an inch

my $fields = [
		{
			name				=> "Company",
			percent				=> 82,
			font_size			=> 12,
			align				=> "left"
		},
		{
			name				=> "Amount",
			percent				=> 18,
			font_size			=> 12,
			align				=> "right",
			aggregate_function	=> "sum",
			type				=> "currency"
		}
	 ];

my $groups = [
	{
		name		=> "GrandTotals",
		data_column	=> 4,
		header		=> [
						{
							percent				=> 100,
							font_size			=> 16,
							align				=> "centre",
							text					=> "Donations to Republican party between 03-Jan-2005 and 10-Jan-2005"
						}
		],
		footer		=> [
						{
							percent				=> 82,
							font_size			=> 12,
							align				=> "right",
							text				=> "Total for month to date"
						},
						{
							percent				=> 18,
							font_size			=> 12,
							align				=> "right",
							aggregate_source	=> 1,
							text				=> "GrandTotals",
							type				=> "currency"
						}
		]
	},
	{
		name		=> "WeekOfMonth",
		data_column	=> 2,
		footer		=> [
						{
							percent				=> 82,
							font_size			=> 12,
							align				=> "right",
							text				=> "Total for week ?"
						},
						{
							percent				=> 18,
							font_size			=> 12,
							align				=> "right",
							aggregate_source	=> 1,
							text				=> "WeekOfMonth",
							type				=> "currency"
						}
		]
	},
	{
		name		=> "FullDate",
		data_column	=> 3,
		header		=> [
						{
							percent				=> 100,
							font_size			=> 12,
							align				=> "left",
							text				=> "?"
						}
		],
		footer		=> [
						{
							percent				=> 82,
							font_size			=> 12,
							align				=> "right",
							text				=> "Total for ?"
						},
						{
							percent				=> 18,
							font_size			=> 12,
							align				=> "right",
							aggregate_source	=> 1,
							text				=> "FullDate",
							type				=> "currency"
						}
		]
	}
];
	
my $report_def = {
					destination			=> "cheques.pdf",
					paper				=> "A4",
					orientation			=> "portrait",
					font_list				=> [ "Times" ],
					default_font			=> "Times",
					default_font_size		=> 12,
					x_margin			=> 10 * mm,
					y_margin			=> 10 * mm
};

my $report = PDF::ReportWriter->new($report_def);
	
#my $records = $dbh->selectall_arrayref(
#	"select
#		Company,
#		round(Amount, 2) as Amount,
#		case
#			when date_format(DateReceived, '%d') between 1 and 7 then 1
#			when date_format(DateReceived, '%d') between 8 and 14 then 2
#			when date_format(DateReceived, '%d') between 15 and 21 then 3
#			when date_format(DateReceived, '%d') between 22 and 28 then 4
#			else 5
#		end as WeekOfMonth,
#		date_format(DateReceived, '%W, %e %b %Y') as FullDate,
#		1 as LotsOfOnes
#	from
#		Cheques
#	where
#		( DateReceived between '$lower_date' and '$upper_date' )
#			and ( Amount is not null and Amount!=0 )
#	order by
#		DateReceived");

my $records = [
				[ "McDonalds", 125000, 1, "Monday, 3rd January 2005" ],
				[ "Ford", 300000, 1, "Monday, 3rd January 2005" ],
				[ "Microsoft", 1000000, 1, "Monday, 3rd January 2005" ],
				[ "The Bin Laden Group", 2500000, 1, "Tuesday, 4th January 2005" ],
				[ "Monsanto", 750000, 1, "Tuesday, 4th January 2005" ],
				[ "News Corporation", 800000, 1, "Tuesday, 4th January 2005" ],
				[ "Procter and Gamble", 250000, 1, "Wednesday, 5th January 2005" ],
				[ "Nestle", 75000, 1, "Thursday, 6th January 2005" ],
				[ "Bayer", 200000, 1, "Thursday, 6th January 2005" ],
				[ "Halliburton", 1500000, 1, "Thursday, 6th January 2005" ],
				[ "Dupont", 750000, 2, "Friday, 7th January 2005" ],
				[ "Exxon Mobil", 200000, 2, "Monday, 10th January 2005" ]
];

my $data = {
				max_font_size		=> 12,
				cell_borders		=> 1,
				no_field_headers	=> 1,
				fields				=> $fields,
				groups				=> $groups,
				data_array			=> $records
};

$report->render_data($data);
$report->save;

system("gpdf cheques.pdf &");
#system("/Applications/Preview.app/Contents/MacOS/Preview cheques.pdf &");