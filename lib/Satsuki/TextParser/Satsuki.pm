use strict;
#------------------------------------------------------------------------------
# システム標準パーサー／Satsukiパーサー
#                                             (C)2006-2015 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
# \x00-\x05は内部で使用するため、いかなる場合も記述できません。
# ※記述してある場合除去されます。
#
package Satsuki::TextParser::Satsuki;
# ※注意。パッケージ名変更時は78行目付近も修正のこと！

use Satsuki::AutoLoader;
our $VERSION = '2.02';
#------------------------------------------------------------------------------
my $TAG_PLUGIN_CLASS = 'TextParser::TagPlugin::Tag_';
my $CSS_CLASS_PREFIX = 'tag-';
my $INFO_BEGIN_MARK = '#---begin_plugin_info';
my $INFO_END_MARK   = '#---end';
#------------------------------------------------------------------------------
# その記事だけの設定を許可する設定値
#   1 文字列
#   2 数値
# ※$self内のハッシュkey
my %allow_override = (asid => 1, chain_line => 2,
 timestamp_date => 1, timestamp_time => 1, 
 anchor_basename =>1, footnote_basename => 1, unique_linkname => 1,
 toc_anchor => 2, toc_level => 2,
 section_count => 2, subsection_count => 2, subsubsection_count => 2,
 section_anchor => 1, subsection_anchor => 1, subsubsection_anchor => 1,
 http_target  => 1, http_class  => 1, http_rel  => 1,
 image_target => 1, image_class => 1, image_rel => 1,
 autolink => 2, br_mode => 2, p_mode => 2, p_class => 1, ls_mode => 1,
 list_nobr => 2, seemore_msg => 1);
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
# 引数のキャッシュファイルは省略しても動作します。
# 第２引数はプラグインdir
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;
	$self->{plugin_cache_file} = shift;

	$self->{use_preprocessor} = 1;
	$self->{timestamp_date} = '%Y/%m/%d';
	$self->{timestamp_time} = '%J:%M';
	$self->{br_mode} = 1;
	$self->{ls_mode} = 1;
	$self->{chain_line} = 1;
	$self->{section_hnum} = 3;	# section level
	$self->{toc_level}    = 1;	# toc は level 0-1 を出力

	$self->init_tags();
	$self->load_plugins(@_);

	return $self;
}

###############################################################################
# ■記法タグのロードルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●記法タグの初期化
#------------------------------------------------------------------------------
sub init_tags {
	my $self = shift;
	$self->{tags} = {};
	$self->{macros} = {};
}

#------------------------------------------------------------------------------
# ●プラグインをロードする
#------------------------------------------------------------------------------
sub load_plugins {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $dir = shift;

	if (!$dir) {
		$INC{'Satsuki/TextParser/Satsuki.pm'} =~ m|(.*/)\w+\.\w+|;
		$dir=$1 . "TagPlugin/";
	}

	my $cfile = $self->{plugin_cache_file};
	my $x = $ROBJ->get_lastmodified($cfile);
	my $y = $ROBJ->get_lastmodified_in_dir($dir);
	if ($x < $y) {
		return $self->generate_plugin_cache($cfile, $dir);
	}
	my $h = $ROBJ->fread_hash_cached($cfile);
	foreach(keys(%$h)) {
		$self->{tags}->{$_} = { plugin => $h->{$_} };
	}
}

sub generate_plugin_cache {
	my $self = shift;
	my $cfile= shift;
	my $dir  = shift;
	my $ROBJ = $self->{ROBJ};

	my $files = $ROBJ->search_files($dir, {ext => '.pm'});
	map { s/^Tag_(\w+)\.pm$/$1/ } @$files;

	# キャッシュファイルが設定されてない場合は全ロードして戻る
	if ($cfile eq '') {
		foreach(@$files) {
			$self->eval_load_plugin($_);
			next;
		}
		return;
	}

	# キャッシュの生成
	my %h = ('::FileVersion' => 1);
	foreach my $f (@$files) {
		my $lines = $ROBJ->fread_lines("${dir}Tag_$f.pm");
		my $in_info;
		foreach(@$lines) {
			$_ =~ s/^\s*//;
			$_ =~ s/[\r\n]*$//;
			if (!$in_info) {
				if ($_ eq $INFO_BEGIN_MARK) { $in_info=1; }
				next;
			}
			if ($_ eq $INFO_END_MARK) { last; }
			#
			# プラグイン情報のパース
			#	$tags->{asin}
			if ($_ !~ /^\$tags->\{("|'|)?([^\}\"\']+)\1\}/) { next; }
			$h{$2} = $f;
			$self->{tags}->{$2} = { plugin => $f };
		}
	}
	# キャッシュに保存
	$ROBJ->fwrite_hash($cfile, \%h);
}


#------------------------------------------------------------------------------
# ●タグ定義のロード
#------------------------------------------------------------------------------
# タグデータ構造
# $tag = $tags{tag_name};
#	$tag{data}   = tag data
#	$tag{argc}   = argments for url data
#	$tag{option} = tag option
# (search only)
#	$tag{name}   = tag name
#	$tag{title}  = title
#	$tag{class}  = html style sheet class
# (alias or html tag)
#	$tag{alias}  = alias to
#	$tag{html}   = html tag
sub load_tagdata {
	my ($self, $data, $allow_load) = @_;
	my $ROBJ = $self->{ROBJ};
	my $file;
	if (!ref($data)) {
		$file = $data;
		$data = $ROBJ->get_filepath( $data );
		if (!-r $data) { return ; }
		$data = $ROBJ->fread_lines_cached( $data, {DelCR => 1} );
	}

	# 現在の設定ロード
	my $basepath = $ROBJ->{Basepath};
	my $tags   = $self->{tags};
	my $macros = $self->{macros};
	my @load_files;
	while(@$data) {
		my $line = shift(@$data);
		chomp($line);
		if (ord($line) == 0x23) { next; }		# 先頭'#'はコメント
		#---------------------------------------------------------------
		# プラグインロード？
		#---------------------------------------------------------------
		if ($line =~ /^plugin\s+(\w+)/i) {
			$self->eval_load_plugin($1);
			next;
		}
		#---------------------------------------------------------------
		# 他のファイルをロード
		#---------------------------------------------------------------
		if ($line =~ /^load\s+([\w\/\.]+)/i) {
			if ($allow_load) { push(@load_files, $ROBJ->get_relative_path($file, $1)); }
			next;
		}
		#---------------------------------------------------------------
		# マクロ定義
		#---------------------------------------------------------------
		if ($line =~ /^\*(.+?)\s*$/) {
			my $tag = $1;
			my @ary;
			while (@$data) {
				my $x = shift(@$data);
				if (ord($x) == 0x23) { next; }	# 先頭 # コメント
				chomp($x);
				if ($x =~ /^\s*$/) { last; }
				unshift(@ary,$x);
			}
			$macros->{$tag} = \@ary;
			next;
		}
		#---------------------------------------------------------------
		# タグ定義
		#---------------------------------------------------------------
		if ($line !~ /^([\w\-\+#:]+)\s*=\s*(.*?)\s*$/s) { next; }	# '=' のない行は無視
		my $tag   = $1;
		my $value = $2;
		$tag =~ s/[\"\']//g;
		my @ary = split(':', $tag);
		if ($#ary > 1) {	# : が２つ以上ある
			my $cmd = shift(@ary); pop(@ary);
			while (@ary) {
				$cmd .= ':' . shift(@ary);
				$tags->{$cmd} ||= {};
			}
		}

		# タグ定義処理
		my $tag_hash = $tags->{$tag} ||= {};

		if (substr($value,0,1) eq '>') {	# alias
			$tag_hash->{alias} = substr($value, 1);

		} elsif (substr($value,0,5) eq 'html:') { # HTMLタグ置換
			my $tag = substr($value, 5);
			$tag =~ s/>/&gt;/g;
			$tag =~ s/</&lt;/g;
			($tag_hash->{html}, $tag_hash->{attribute}) = split(/\s+/, $tag, 2);
			if ($tag_hash->{attribute} ne '') {
				$tag_hash->{attribute} = ' ' . $tag_hash->{attribute};
			}
		} elsif (substr($value,0,5) eq 'text:') { # text置換
			my $text = substr($value, 5);
			$text =~ s/^\s*(.*?)\s*$/$1/g;
			$tag_hash->{data} = $text;
			$tag_hash->{argc} = 9;
			$tag_hash->{replace_html} = 1;

		} elsif (substr($value,0,7) eq 'plugin:') { # プラグイン設定
			my $plg = substr($value, 7);
			if ($plg =~ /[^\w]/) { next; }
			$tag_hash->{plugin} = $plg;
		} else {
			if (substr($value,0,1) eq '<') {	# HTML置換
				$value = "$tag,ASCII,9," . $value;
			}
			# タグの（リンク）クラス
			my $class =$tag;
			$class =~ s/#.*//;
			$tag_hash->{name} = $class;
			$class =~ s/[^A-Za-z0-9 ]/-/g;
			$tag_hash->{class} = "$CSS_CLASS_PREFIX$class";
			# タイトルなど
			my ($title, $option, $url) = split(/\s*,\s*/, $value, 3);
			$ROBJ->tag_escape( $title, $option );
			if ($url =~ /^(\d+)\s*,\s*(.*)$/) {	# 受け取り引数指定
				$tag_hash->{argc} = $1;
				$url = $2;
			} else {
				$tag_hash->{argc} = 1;
				$url .= '$1';
			}
			$url =~ s/\"/&quot;/g;
			if ($title  ne '') { $tag_hash->{title}  = $title;  }
			if ($option ne '') { $tag_hash->{option} = $option; }
			if ($url eq 'block:') {	# block要素ならば、空行が出るまで読み込み
				$url = '';
				while(@$data) {
					my $add = shift(@$data);
					chomp($add);
					# $add =~ s/^\s*(.*?)\s*\n?$/$1/;	# 前後の空白除去
					if ($add eq '') { last; }
					$url .= $add;
				}
			}
			if ($url ne '') {
				my $s1 = substr($url, 0, 1);
				$tag_hash->{data} = $url;
				if (substr($url,0,1) eq '<') {	# HTML置換
					$tag_hash->{replace_html}=1;
				}
			}
		}
	}
	# 他のファイルロード（エラーなし）
	foreach(@load_files) {
		$self->load_tagdata( $_ );
	}
}

#------------------------------------------------------------------------------
# ●プラグインのロード
#------------------------------------------------------------------------------
sub eval_load_plugin {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $file = shift;
	$file =~ s/[^\w]//g;
	# $ROBJ->debug("load tag plugin '$file'");
	eval{ $ROBJ->loadpm("${TAG_PLUGIN_CLASS}$file", $self->{tags}); };
	if ($@) { $ROBJ->error('[plugin load failed] %s', $@); }
}

###############################################################################
# ■プリプロセッサー
###############################################################################
#------------------------------------------------------------------------------
# ●記事元データ（本文）の加工
#------------------------------------------------------------------------------
# *t* の時刻付き見出し記法用
#
# $parser->preprocessor($text);
# $parser->preprocessor($text, {key_list => 1});
#
sub preprocessor {
	my $self = shift;
	my $opt = $_[1];

	# *t* がなく、key記法がなければ何もしない
	if ($_[0] !~ /\*t[\*:]/ && (!$opt->{key_list} || $_[0] !~ /\[key:.*?\]/)) { return []; }

	# 0x00の除去
	$_[0] =~ s/\x00//g;

	# コメントやブロックの退避
	my $backup = $self->backup_blocks($_[0]);

	# 置換処理
	my $now_tm = $self->{ROBJ}->{TM} || time();
	# *t*section, **t*section
	$_[0] =~ s/(?:\G|\n)\*(\*?)t([\*\:])/"\n*$1" . ($now_tm++) . $2/eg;

	# key list
	my @key_list;
	if ($opt->{key_list}) {
		while($_[0] =~ m/\[key:([^:\]]+)(?:\:.*?)?\]/g) { push(@key_list, $1); }
	}

	# ブロックの復元
	$self->restore_blocks($_[0], $backup);

	return \@key_list;
}

#------------------------------------------------------------------------------
# ●データ加工のために、ブロック退避
#------------------------------------------------------------------------------
sub backup_blocks {
	my $self = shift;
	my @ary;
	$_[0] .= "\n";
	$_[0]  =~ s/(<!--.*?-->|\{.*?\}|(?:\G|\n)>+(?:\[|\|\||\|\w+).*?\n\#?(\]|\|\|)<+\n)/push(@ary, $1), "\n\x00$#ary\x00\n"/esg;
	$_[0]  =~ s/(\{\{[^\}]*\}\}|\{[^\}]*\})/push(@ary, $1), "\x00$#ary\x00"/eg;
	return \@ary;
}

sub restore_blocks {
	my $self = shift;
	my $ary  = $_[1];
	$_[0] =~ s/\n\x00(\d+)\x00\n/$ary->[$1]/g;
	chomp($_[0]);
	return $_[0];
}

###############################################################################
# ■メインルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●記事本文の整形
#------------------------------------------------------------------------------
sub text_parser {
	my ($self, $lines, $opt) = @_;
	$lines = [ split(/\n/, $lines) ];
	$opt ||= {};	# オプション

	# 初期設定
	$self->{sections}       = [];	# 空のarray
	$self->{subsections}    = [];
	$self->{subsubsections} = [];
	$self->{options}        = {};	# 空のhash
	$self->{vars}         ||= {};	# タグ置換用データ。内部自由変数
	$self->{section_count}     = int($opt->{section_count});	# section counter
	$self->{subsection_count}  = int($opt->{subsection_count});	# sub-section counter

	# ユニークリンク名の生成
	$self->init_unique_link_name();

	# 内部変数の退避
	my %backup;
	foreach(keys(%allow_override)) {
		$backup{$_} = $self->{$_};
	}
	my %backup_vars = %{ $self->{vars} };

	# [01]ブロック処理、コメント除去処理
	$lines = $self->block_parser($lines);

	# [02]tableやリストなどのブロック処理、セクション処理
	$lines = $self->blocks_and_section($lines);

	# 内部変数復元（[02]での最終オーバーライド結果を[03]で使わないため）
	foreach(keys(%allow_override)) { $self->{$_} = $backup{$_}; }

	# [03]記法タグの処理
	$lines = $self->replace_original_tag($lines);

	# [04]段落/改行処理
	$lines = $self->paragraph_processing($lines);

	# [99]後処理
	my $data = join('', @$lines);
	$self->post_process( \$data );

	# 内部変数の復元
	foreach(keys(%allow_override)) { $self->{$_} = $backup{$_}; }
	$self->{vars_}= $self->{vars};
	$self->{vars} = \%backup_vars;
	$self->restore_unique_link_name();

	# エスケープした文字列の復元
	if (! $self->{escape_no_dencode}) {
		# ( ) [ ] { } | * ^ ~: = + - を復元
		$self->un_escape( $data );
	}

	# Moreの処理
	my $short;
	if ($self->{more_read}) {
		$short=$data;
		$data =~ s/\s*<p\s*class="seemore">.*?<!--%SeeMore%-->/<!--%SeeMore%-->/g;
		$data =~ s/\n?<!--%MoreEnd%-->\n//;
		$short=~ s/<!--%SeeMore%-->.*?<!--%MoreEnd%-->//sg
	}
	return wantarray ? ($data, $short) : $data;
}

#------------------------------------------------------------------------------
# ●unique_link_nameの生成と破棄
#------------------------------------------------------------------------------
sub init_unique_link_name {
	my $self = shift;
	$self->{unique_linkname_bak} = $self->{unique_linkname};
	$self->{unique_linkname} ||= 'k'.($self->{thispkey} || int(rand(0x80000000)));
}
sub restore_unique_link_name {
	my $self = shift;
	$self->{unique_linkname} = $self->{unique_linkname_bak};
}

###############################################################################
# ■[01] 前処理と「>>??<<」系のブロック処理、コメント除去処理
###############################################################################
# 行末改行のある行は処理終了とみなす。
sub block_parser {
	my ($self, $lines) = @_;
	my @ary;
	my ($block_start, $block_end, $block_tag);
	my $p     = 1;	# 段落処理有効モード、0:そのまま入力モード
	my $tag   = 1;	# htmlタグ有効モード
	my $atag  = 1;	# adiary拡張タグ有効モード
	my $bcom  = 0;	# ブロック中コメント有効モード
	my $br    = 0;	# 行末、強制<br>モード
	my $cite='';	# 閉じタグの手前（blockquoteの下部等）に付けるHTML
	my $macros = $self->{macros};	# マクロ情報
	my @block_stack;
	my $in_comment = 0;
	
	my $block_close = sub {
		if ($block_tag eq '<!--') {
			push(@ary, "-->\n\x01");
		} elsif ($block_tag eq 'script') {
			push(@ary, "--></script>\n\x01");
		} elsif ($p) {
			push(@ary, "$cite</$block_tag>\n");
		} else {
			push(@ary, "$cite</$block_tag>\n\x01");
		}
		($block_end, $block_tag, $p, $tag, $atag, $bcom, $br, $cite) = @{ pop(@block_stack)};
	};
	while($#$lines >= 0) {
		my $line = shift(@$lines);
		$line =~ s/[\x00-\x03]//g;
		my $line_orig = $line;
		# コメント中である
		if ($in_comment) {
			my $x = index($line, '-->');
			if ($x < 0) { next; }		# コメント中は出力しない
			# コメントが閉じられている
			$in_comment = 0;
			$line = substr($line, $x +3);	# 残り
		}
		#-------------------------------------------------
		# エスケープ記法の置換処理
		#-------------------------------------------------
		if ($atag) {	# adiary拡張tagが有効
			# 行末 \ による行連結
			while($self->{chain_line} && substr($line, -1) eq "\\") {
				chop($line);
				$line  =~ s/ +$//;	# \ の手前のスペース除去
				$line .= shift(@$lines);
			}
			# mini verbatim表記  {xxx}, {<tag>}, {[xxx:tag]}
			$line =~ s/\\([\{\}])/ "\x01#" . ord($1) . ';'/eg;	# { } のエスケープ
			$line =~ s/\{\{(.*?)\s?\}\}|(\[\[.*?\]\])/
				$2 ? $2 : $self->mini_pre($1) /eg;		# mini pre {{ xxx }}
			$line =~ s/\{(.*?)\s?\}|(\[\[.*?\]*\]\])/
				$2 ? $2 : $self->mini_verbatim($1) /eg;		# mini varbatim {<xxx>}
			# $line =~ tr/\x01/&/;	# \x01 を & に戻す
			$line =~ s/\x01#(\d+);/chr($1)/eg;	# { } を戻す
			# マクロ展開
			$line =~ s#\[\*toc(\d*)(?:|:(.*?))\]#<toc>level=$1:$2</toc>\n#g;
			$line =~ s/\[\*(.*?)\]/ $macros->{$1} && unshift(@$lines, @{ $macros->{$1} }), ''/eg;
		}
		#-------------------------------------------------
		# コメント除去
		#-------------------------------------------------
		if ($atag && $line ne '') {	# 記法タグが有効
			$line =~ s/<!--.*?-->//g;		# コメント除去
			my $x = index($line, '<!--');
			if ($x >= 0) {				# コメントがある
				$in_comment = 1;
				$line = substr($line, 0, $x);	# 手前
			}
		}
		#-------------------------------------------------
		# ブロック記法の開始処理
		#-------------------------------------------------
		if ($atag && ord($line) == 0x3e) {	# 記法タグ有効 && 最初の文字が">"
			my $new_block_end;
			my $dc;		# デフォルトクラス
			my $line_opt;
			my $len;
			my $block_tag_add='';
			my $s10= substr("$line ", 0, 10);
			my $s2 = substr($s10, 0, 2);
			my $s3 = substr($s10, 0, 3);
			my $s4 = substr($s10, 0, 4);
			my $s5 = substr($s10, 0, 5);
			my $s6 = substr($s10, 0, 6);
			# $p		段落処理を行う
			# $tag		htmlタグが有効
			# $atag		記法タグが有効
			# $bcom		ブロック中コメントon
			$cite="";
			if ($s2 eq '>|') {
			  push(@block_stack, [$block_end, $block_tag, $p, $tag, $atag, $bcom, $br, $cite]);
			  if ($line =~ /^>\|([\w#\-]+|\?)\|(.*)/) {
				$len = 3+length($1);
			  	if ($1 eq 'aa')  { $new_block_end = '||<'; $block_tag='div'; $p=$tag=$atag=0; $br=1; $dc=" ascii-art"; }
				else {
					# シンタックスハイライト記法
					$new_block_end = '||<'; $block_tag='pre'; $p=$tag=$atag=0; $dc=" syntax-highlight";
					my $lang = $1;
					if ($lang =~ /^\w[\w\-]*$/) { $dc .= ' ' . $lang; }
				}
				$line_opt = $2;
			  }
			  elsif ($s10 eq '>||script ') { $len=10; $new_block_end = '||<'; $block_tag='script'; $p=$tag=$atag=$br=0; }
			  elsif ($s10 eq '>||comment') { $len=10; $new_block_end = '||<'; $block_tag='<!--';   $p=$tag=$atag=$br=0; }
			  elsif ($s4 eq '>||#')  { $len=4; $new_block_end = '#||<'; $block_tag='pre'; $p=$tag=$atag=0; $bcom=1; }
			  elsif ($s6 eq '>||aa '){ $len=6; $new_block_end =  '||<'; $block_tag='div'; $p=$tag=$atag=0; $br=1; $dc=" ascii-art"; }
			  elsif ($s4 eq '>|?|')  { $len=4; $new_block_end =  '||<'; $block_tag='pre'; $p=$tag=$atag=0; $dc=" syntax-highlight"; }
			  elsif ($s3 eq '>||')   { $len=3; $new_block_end =  '||<'; $block_tag='pre'; $p=$tag=$atag=0; }
			  elsif ($s2 eq '>|')    { $len=2; $new_block_end =   '|<'; $block_tag='pre'; $p=0; }
			} elsif ($s3 eq '>>>') {
			  push(@block_stack, [$block_end, $block_tag, $p, $tag, $atag, $bcom, $br, $cite]);
			     if ($s5 eq '>>>||') { $len=5; $new_block_end ='||<<<'; $block_tag='div'; $p=$tag=$atag=0; }
			  elsif ($s4 eq '>>><')  { $len=4; $new_block_end = '><<<'; $block_tag='div'; $p=$tag =0; }
			  elsif ($s4 eq '>>>[')  { $len=4; $new_block_end = ']<<<'; $block_tag='div'; $p=$atag=0; }
			  elsif ($s4 eq '>>>|')  { $len=4; $new_block_end = '|<<<'; $block_tag='div'; $p=0; }
			  elsif ($s3 eq '>>>')   { $len=3; $new_block_end =  '<<<'; $block_tag='div'; }

			} elsif ($s2 eq '>>') {
			  push(@block_stack, [$block_end, $block_tag, $p, $tag, $atag, $bcom, $br, $cite]);
			     if ($s4 eq '>>||')  { $len=4; $new_block_end = '||<<'; $block_tag='blockquote'; $p=$tag=$atag=0; }
			  elsif ($s3 eq '>>|')   { $len=3; $new_block_end =  '|<<'; $block_tag='blockquote'; $p=0; }
			  elsif ($s6 eq '>>del '){ $len=6; $new_block_end =   '<<'; $block_tag='del'; }
			  elsif ($s6 eq '>>ins '){ $len=6; $new_block_end =   '<<'; $block_tag='ins'; }
			  elsif ($s2 eq '>>')    { $len=2; $new_block_end =   '<<'; $block_tag='blockquote'; }
			} elsif ($line  =~ m!^>(https?://[^>]*)>(.*)!) {
			  push(@block_stack, [$block_end, $block_tag, $p, $tag, $atag, $bcom, $br, $cite]);
			  	  $new_block_end = '<<'; $block_tag='blockquote';
			  	  $line_opt = "[$1]$2";
			}

			# \x01 インデント、[]タグ抑止マーク
			if ($new_block_end) {
				$block_end = $new_block_end;
				my $class  = ($line_opt ne '' ? $line_opt : substr($line, $len) . $dc);
				my $add_attr;
				if ($block_tag eq 'blockquote' && $class =~ m|^(\[(&?https?://[^:\"\]]*)[^\]]*\])(.*)|) {	# タグ指定？
					$add_attr = " cite=\"$2\"";
					$cite  = "<cite>$1</cite>";
					$class = $3;
				}
				if (!$dc && $class =~ /[^\w\-= ]/) {	# クラス名以外の文字等が続く場合は開始タグとして認識しない
					($block_end, $block_tag, $p, $tag, $atag, $bcom, $br, $cite) = @{ pop(@block_stack)};
				} else {
					if ($block_tag eq '<!--')   { push(@ary, "<!--\x01"); next; }
					if ($block_tag eq 'script') { push(@ary, "<script$class><!--\x01"); next; }
					if ($class ne '') {	# クラス, ID指定
						$class = $self->parse_class_id($class);
					}
					if ($block_tag eq 'pre') { push(@ary, "<pre$add_attr$class>$block_tag_add\x01"); }
							    else { push(@ary, "<$block_tag$add_attr$class>\n"); }
					next;
				}
			}
		}
		#-------------------------------------------------
		# ブロック中の処理
		#-------------------------------------------------
		if ($block_end) {
			# ブロックの終わり
			if ($line eq $block_end) {
				&$block_close();
				next;
			}
			# script環境
			if ($block_tag eq 'script') {
				$line =~ s/--/==/g;
				push(@ary, "$line\n\x01");	# そのまま出力（インデント不可）
				next;
			}
			if ($block_tag eq '<!--') {
				$line =~ s/--/==/g;
				push(@ary, "$line\n");		# そのまま出力
				next;
			}			# HTMLタグ無効ブロック
			if (! $tag) {	# htmlタグ、[]タグ無効、ブロックコメント有効
				$line =~ s/&/&amp;/g;
				$line =~ s/</&lt;/g;
				$line =~ s/>/&gt;/g;
			}
			# ブロック中コメント機能
			if ($bcom) {
				$line =~ s/##(\{(.+?)\}|\[(.+?)\]|\|(.+?)\|)/<strong class="comment">$2$3$4<\/strong>/g;
				$line =~  s/#(\{(.+?)\}|\[(.+?)\]|\|(.+?)\|)/<span class="comment">$2$3$4<\/span>/g;
			}
			# [tag] 形式の記法タグが無効
			if (! $atag && $bcom) {			# ((?)) 注釈だけ有効にする：ブロック中コメント機能
				$line =~ s/([\[\]\{\}\|:])/'&#' . ord($1) . ';'/eg;
				$line =~ s/^([\-\+\*=])/   '&#' . ord($1) . ';'/e;
			} elsif (! $atag) {
				$line =~ s/([\[\]\{\}\|:\(\)])/'&#' . ord($1) . ';'/eg;
				$line =~ s/^([\-\+\*=])/       '&#' . ord($1) . ';'/e;
			} else {
				$line =~ s/^====/&#61;===/;	# ブロック中は続きを読む表記を無効化
			}
			# 強制行末改行モード
			if ($br) {
				$line .= "<br>";
			}
			# 段落処理なしモード
			if (! $p) {
				push(@ary, "$line\n\x01");	# \x01 インデント抑止マーク
				next;
			}

		}
		#-------------------------------------------------
		# 行処理
		#-------------------------------------------------
		if ($line eq '') {
			if ($line_orig ne '') { next; }
			my $c = 1;
			while($#$lines >= 0) {
				if ($lines->[0] ne '') { last; }
				shift(@$lines);
				$c++;
			}
			push(@ary, {null_lines => $c});
			next;
		}
		#-------------------------------------------------
		# 通常行
		#-------------------------------------------------
		push(@ary, $line);
	}
	# block が終わってないとき
	while ($block_end) {
		&$block_close();
		next;
	}

	return \@ary;
}

#--------------------------------------------------------------------
# ○ミニ verbatim 記法
#--------------------------------------------------------------------
sub mini_verbatim {
	my ($self, $line) = @_;
	$self->tag_syntax_escape($line);	# tagエスケープ
	return $line;
}

#--------------------------------------------------------------------
# ○ミニ pre 記法
#--------------------------------------------------------------------
sub mini_pre {
	my ($self, $line) = @_;
	$self->tag_syntax_escape($line);	# tagエスケープ
	return "<span class=\"mono\">$line</span>";
}


###############################################################################
# ■[02] table/リストのブロック処理、セクション処理
###############################################################################
# 行末改行のある行は処理終了とみなす。
my %marks;
$marks{'*'}     = \&section;
$marks{'**'}    = \&subsection;
$marks{'***'}   = \&subsubsection;
$marks{'****'}  = \&subsubsubsection;
$marks{'|'}     = \&table;
$marks{'='}     = \&dummy;
$marks{'=='}    = \&dummy;
$marks{'==='}   = \&dummy;
#$marks{'===='}  = \&more_read;
$marks{'===='}  = \&super_more_read;
$marks{'====='} = \&super_more_read;

sub blocks_and_section {
	my ($self, $lines) = @_;
	my $ROBJ = $self->{ROBJ};
	my @ary;
	my $class;
	my $id;

	# 変数初期化
	$self->{in_section}       = 0;
	$self->{more_read}        = 0;
	$self->{now_anchor_name}  = "$self->{unique_linkname}p0";	# default
	$self->{tr_count}         = 0;
	$self->{table_rows}       = undef;	# table buffer

	# 先頭が見出しでない場合、section を開始する
	if (ref($lines->[0])) { shift(@$lines); }	# 行頭改行無視
	foreach(@$lines) {
		if ($_ =~ /^::/ || $_ eq "" || ref($_)) { next; }
		if (substr($_, 0, 1) ne '*' || substr($_, 0, 2) eq '**') {
			$self->{in_section} = 1;
			push(@ary, "<section>\n");
		}
		last;
	}

	my $in_table;
	push(@$lines, "\n");	# dummy line
	while($#$lines >= 0) {
		my $line = shift(@$lines);
		# $s1-$s3 先頭 1byte-3byte
		my $s1 = substr($line, 0, 1);
		my $s2 = substr($line, 0, 2);
		my $s3 = substr($line, 0, 3);
		#-------------------------------------------------
		# テーブルの出力？
		#-------------------------------------------------
		if ($in_table && $s1 ne '|') {
			$self->table_output( \@ary, $class );
			$class='';
			$in_table = undef;
		}
		#-------------------------------------------------
		# 処理済み行は飛ばす
		#-------------------------------------------------
		my $end_mark = substr($line, -1);		# \n/\x01 で終わる行は処理済み
		if (ref($line) || $end_mark eq "\n" || $end_mark eq "\x01") {
			push(@ary, $line);
			next;
		}

		#-------------------------------------------------
		# table/listブロック判別
		#-------------------------------------------------
		# 自由変数に設定
		if ($s3 eq ':::') {
			# 記法タグの部分で処理する
			push(@ary, $line);
			next;
		# クラス指定表記 / 内部変数書き換え
		} elsif ($s2 eq '::' && length($line)>2) {
			$class = substr($line, 2);
			if ($class =~ /^(\w+)\s*=\s*(.*)/) {
				# 一時的な内部変数書き換え（記法タグの時も処理する）
				if ($allow_override{$1}==1) {
					$self->{$1}=$2;
					push(@ary, "::$1=$2");
					$ROBJ->tag_escape( $self->{$1} );
				} elsif ($allow_override{$1}==2) {
					$self->{$1}=int($2);
					push(@ary, "::$1=$self->{$1}");
				}
				if (lc($1) ne 'id') {
					$class='';
					next;
				}
			}
			$class = $self->parse_class_id($class);
			next;
		}
		if ($s1 eq ':') {	# : のリスト表記
			push(@ary, "<dl$class>\n"); $class='';
			my $list_ext;
			if ($line eq '::') {
				$list_ext=1;
			} else {
				unshift(@$lines, $line);
			}
			while(@$lines && ord($lines->[0]) == 0x3a) {
				$line = shift(@$lines);
				my @add;
				if ($list_ext) {
					my $block_c=0;
					while(@$lines) {
						my $x = $lines->[0];
						if (ref($x) || ord($x) == 0x3a) { last; }
						# 内部ブロック要素、対応チェック
						if ($x =~ m[^\t*</(?:blockquote|div|pre)>[\n\x01]$]) {
							$block_c--;if ($block_c<0) { last; }
						} elsif ($x =~ m[^\t*<(?:blockquote|div|pre)[^>]*>[\n\x01]$]) {
							$block_c++;
						}
						push(@add, shift(@$lines));
					}
				}
				# タグ中の : を処理しないため先にパースする
				$line = $self->parse_tag($line);
				my ($dummy, $dt, $dd) = split(':', $line, 3);
				if (@add) {
					my $br; if ($self->{br_mode}) { $br='<br>'; }
					push(@ary, "\t<dt>$dt</dt><dd>$dd$br\n", @add, "\t</dd>\n");
				} else {
					push(@ary, "\t<dt>$dt</dt><dd>$dd</dd>\n");
				}
				# リスト項目後の空行１行は無視
				if ($list_ext && ref($lines->[0]) && $lines->[0]->{null_lines}==1) { shift(@$lines); }
			}
			push(@ary, "</dl>\n");
			next;
		}
		if ($s1 eq '+' || $s1 eq '-') {   # -/+ のリスト表記
			my $list_ext;
			if (length($line)==1) { $list_ext=1; } 
					else  { unshift(@$lines, $line); }
			$self->split_list_block(\@ary, $lines, 1, $class, $list_ext);
			next;
		}
		if (!$in_table && $s1 eq '|') {	# | のテーブル表記
			$in_table = 1;
		}
		#-------------------------------------------------
		# セクション、続きを読むの判別
		#-------------------------------------------------
		my $mark = substr($line, 0, 1);
		if (exists $marks{$mark}) {
			for(my $i=2; $i<6 ;$i++) {
				my $x = substr($line, 0, $i);
				if (! exists $marks{$x}) { last; }
				$mark = $x;
			}
			my $rewrite = &{ $marks{$mark} }($self, $line);
 			if (!defined $rewrite) { next; }
			if (ref($rewrite)) {  push(@ary, @$rewrite); } else { push(@ary, $rewrite); }
			next;
		}
		# 行頭 - * の手前に半角スペースを置くエスケープ処理対応
		if (ord($line) == 0x20 && index(' - + * | : = > < #', substr($line, 0, 2)) > 0) {
			push(@ary, substr($line, 1));
			next;
		}
		#-------------------------------------------------
		# 通常行
		#-------------------------------------------------
		push(@ary, $line);
	}
	if ($self->{more_read})  { push(@ary, "<!--%MoreEnd%-->\n"); }
	if ($self->{in_section}) {
		push(@ary, {section_end => 1});	# 位置をマーキング
		push(@ary, "</section>\n");
	}

	# セクションタイトルのタグの処理
	my $func;
	$func = sub {
		my $ary = shift;
		foreach(@$ary) {
			$_->{title} = $self->parse_tag( $_->{title} );	# タグ処理
			$_->{title} =~ s/\(\(.*?\)\)//g;		# 注釈の削除
			my $subs = $_->{children};
			if (!$subs || !@$subs) { next; }
			&$func($subs);
		}
	};
	&$func($self->{sections});

	return \@ary;
}

#--------------------------------------------------
# ○リストブロックの抽出
#--------------------------------------------------
sub split_list_block {
	my ($self, $ary, $lines, $depth, $class, $list_ext) = @_;
	my $tag = 'ul';
	my $indent = "\t" x ($depth-1);
	if (substr($lines->[0], 0, 1) eq '+') { $tag='ol'; }
	push(@$ary, "$indent<$tag$class>\n");
	my $next_line;
	while(@$lines) {
		if (ref($lines->[0]) || $lines->[0] !~ /^([\+\-]+)(.*)/) { last; }
		my $length = length($1);
		my $data   = $2;
		if ($length < $depth) { last; }
		if ($length > $depth) {
			if ($next_line) {
				if ($next_line !~ /^\t*$/) { push(@$ary, "$next_line\n"); }
				$next_line='';
				$self->split_list_block($ary, $lines, $depth+1, '', $list_ext);
				push(@$ary, "$indent\t</li>\n");
				next;
			}
			$self->split_list_block($ary, $lines, $depth+1, '', $list_ext);
			next;
		}
		shift(@$lines);
		if ($next_line) { push(@$ary, "$next_line</li>\n"); }
		if ($data =~ /^=(\d+)(?:\s+(.*))?/) {	# 項目値指定
			$next_line = "$indent\t<li value=\"$1\">$2";
		} else {
			$next_line = "$indent\t<li>$data";
		}
		# 拡張リスト処理
		if ($list_ext) {
			my $f=1;
			my $block_c=0;
			while(@$lines) {
				my $x = $lines->[0];
				if (ref($x) || $x =~ /^[\+\-]/) { last; }
				# 内部ブロック要素、対応チェック
				if ($x =~ m[^\t*</(?:blockquote|div|pre)>[\n\x01]$]) {
					$block_c--;if ($block_c<0) { last; }
				} elsif ($x =~ m[^\t*<(?:blockquote|div|pre)[^>]*>[\n\x01]$]) {
					$block_c++;
				}
				if ($f) {
					my $br = $self->{list_nobr} ? '' : '<br>';
					push(@$ary, "$next_line$br\n");		# ブロック終わり記号
					$next_line="$indent\t"; $f=0
				}
				# リスト内改行への対応（p modeでもbrで処理）
				my $br;
				if (!$self->{list_nobr} && $x !~ /[\n\x01]$/) {
					$br = "<br>\n";
				}
				push(@$ary, shift(@$lines) . $br);
			}
			# リスト項目後の空行１行は無視
			if (ref($lines->[0]) && $lines->[0]->{null_lines}==1) { shift(@$lines); }
		}
	}
	if ($next_line) { push(@$ary, "$next_line</li>\n"); }
	push(@$ary, "$indent</$tag>\n");
}

#------------------------------------------------------------------------------
# ●記法ルーチン
#------------------------------------------------------------------------------
#--------------------------------------------------------------------
# ダミー（何もせずそのまま）
#--------------------------------------------------------------------
sub dummy {
	return $_[1];
}

#--------------------------------------------------------------------
# *section_title
#--------------------------------------------------------------------
sub section {
	my ($self, $line) = @_;
	my $ROBJ = $self->{ROBJ};
	my @ary;

	# section の終わり
	if ($self->{in_section}) {
		push(@ary, {section_end => 1});	# 位置をマーキング
		push(@ary, "</section>\n");
	}

	# section の開始
	if ($self->{in_section}) { push(@ary, "\n"); }
	push(@ary, "<section>\n");
	$self->{in_section} = 1;

	# セクションカウンタの処理
	my $sec_c = $self->{section_count} += 1;
	$self->{subsection_count} = 0;
	$self->{subsubsection_count} = 0;

	# 見出しの処理
	$line = substr($line, 1);
	my $anchor =  $self->{section_anchor};
	my $name   = ($self->{anchor_basename} || "$self->{unique_linkname}p") . $sec_c;
	if ($line =~ /^([\w\-\.\d]+)(:[^\*]+)?\*(.*)/s) {
		$name = $1;
		$line = $3;
		my $force_format = substr($2,1);
		if ($name > 100000000) {	# 時刻記法
			my $ROBJ = $self->{ROBJ};
			my $format = $self->{timestamp_time} || '%J:%M';
			my $h = $ROBJ->time2timehash( $name );
			my $ymd = sprintf("%04d%02d%02d", $h->{year}, $h->{mon}, $h->{day});
			if ($ymd != $self->{thisymd}) {
				$format = $self->{timestamp_date} || '%Y/%m/%d';
			}
			$format = $force_format || $format;
			$line .= ' <span class="timestamp">'
				. $ROBJ->tm_printf($format, $name) . '</span>';
		}
	}

	$anchor =~ s/%n/$sec_c/g;
	$self->{now_anchor_name} = $name;
	$self->{subsections} = [];
	# セクション情報の保存
	push(@{ $self->{sections} }, {
		name => $name,
		title => $line,
		anchor => $anchor,
		section_count => $sec_c,
		children => $self->{subsections}
	});

	my $hnum = $self->{section_hnum};
	if ($anchor ne '') { $anchor="<span class=\"sanchor\">$anchor</span>"; }
	push(@ary, "<h$hnum><a href=\"$self->{thisurl}#$name\" id=\"$name\">$anchor$line</a></h$hnum>\n");
	return \@ary;
}

#--------------------------------------------------------------------
# **subsection_title
#--------------------------------------------------------------------
sub subsection {
	my ($self, $line) = @_;
	$line = substr($line, 2);

	# セクションカウント
	my $sec_c    = $self->{section_count};
	my $subsec_c = $self->{subsection_count} += 1;
	$self->{subsubsection_count} = 0;

	my $anchor = $self->{subsection_anchor};
	my $name   = $self->{now_anchor_name};
	$name .= '.' . $subsec_c;
	$self->{now_subanchor_name} = $name;
	$anchor =~ s/%n/$sec_c/g;
	$anchor =~ s/%s/$subsec_c/g;
	if ($line =~ /^([\w\-\.\d]+)(:[^\*]+)?\*(.*)/s) {
		$name = $1;
		$line = $3;
		my $force_format = substr($2,1);
		if ($name > 100000000) {	# 時刻記法
			my $ROBJ = $self->{ROBJ};
			my $format = $self->{timestamp_time} || '%J:%M';
			my $h = $ROBJ->time2timehash( $name );
			my $ymd = sprintf("%04d%02d%02d", $h->{year}, $h->{mon}, $h->{day});
			if ($ymd != $self->{thisymd}) {
				$format = $self->{timestamp_date} || '%Y/%m/%d';
			}
			$format = $force_format || $format;
			$line .= ' <span class="timestamp">'
				. $self->{ROBJ}->tm_printf($format, $name) . '</span>';
		}
	}
	# セクション情報の保存
	$self->{subsubsections} = [];
	push(@{$self->{subsections}}, {
		name => $name,
		title => $line,
		anchor => $anchor,
		section_count => $sec_c,
		subsection_count => $subsec_c,
		children => $self->{subsubsections}
	});

	my $hnum = $self->{section_hnum} +1;
	if ($anchor ne '') { $anchor="<span class=\"sanchor\">$anchor</span>"; }
	return "<h$hnum><a href=\"$self->{thisurl}#$name\" id=\"$name\">$anchor$line</a></h$hnum>\n";
}

#--------------------------------------------------------------------
# ***subsubsection
#--------------------------------------------------------------------
sub subsubsection {
	my ($self, $line) = @_;
	$line = substr($line, 3);

	# セクションカウント
	my $sec_c     = $self->{section_count};
	my $subsec_c  = $self->{subsection_count};
	my $sub2sec_c = $self->{subsubsection_count} += 1;

	my $anchor = $self->{subsubsection_anchor};
	$anchor =~ s/%n/$sec_c/g;
	$anchor =~ s/%s/$subsec_c/g;
	$anchor =~ s/%t/$sub2sec_c/g;
	my $name = ($self->{now_subanchor_name} || "$self->{now_anchor_name}.$subsec_c")  . ".$sub2sec_c";

	# セクション情報の保存
	push(@{$self->{subsubsections}}, {
		name => $name,
		title => $line,
		anchor => $anchor,
		section_count => $sec_c,
		subsection_count => $subsec_c,
		sub2section_count => $sub2sec_c
	});

	my $hnum = $self->{section_hnum} +2;
	if ($anchor ne '') { $anchor="<span class=\"sanchor\">$anchor</span>"; }
	return "<h$hnum><a href=\"$self->{thisurl}#$name\" id=\"$name\" class=\"linkall\">$anchor$line</a></h$hnum>\n";
}

#--------------------------------------------------------------------
# ***subsubsection
#--------------------------------------------------------------------
sub subsubsubsection {
	my ($self, $line) = @_;
	$line =~ /^\*(\*+)(.*)/s;
	my $level = length($1) + $self->{section_hnum};
	if (6<$level) { $level=6; }
	return "<h$level>$2</h$level>\n";
}

#--------------------------------------------------------------------
# table記法- |name|data
#--------------------------------------------------------------------
sub table {
	my ($self, $line) = @_;
	$line =~ s/\s*$//;	# 行末空白の除去

	# caption/summary
	if ($self->{table_rows} || substr($line,-1) eq '|') {
		# tableが既に記述済 か | で終わるときは何もしない
	} elsif (substr($line,0,9) eq '|caption=') {
		$self->{table_caption} = substr($line,9);
		return;
	} elsif (substr($line,0,9) eq '|summary=') {
		$self->{table_summary} = substr($line,9);
		return;
	}

	# table 内クラス指定
	if (substr($line,0,3) eq '|::') {
		my $class = substr($line,3);
		$class =~ s/[^\w\-\| ]//g;
		# th, td クラス指定
		if (substr($class,0,1) eq '|') {
			my @ary = split(/\s*\|\s*/, $class);
			shift(@ary);	# 読み捨て
			$self->{td_classes} = \@ary;
			return;
		}
		# trクラス指定
		$self->{tr_class} = " $class";
		return undef;
	}

	# table 1 ROW の作成
	my $rows = $self->{table_rows} ||= [];
	my @cols;

	# |aa|bb|cc  → |aa|bb|cc|=
	# |aa|bb|cc| → |aa|bb|cc|=
	$line =~ s/\|?\s*$/|=/;
	my @ary = split(/\s*\|\s*/, $line);
	shift(@ary);	# 最初を読み捨て
	pop(@ary);	# "=" 読み捨て

	my $td_classes = $self->{td_classes} || [];
	my @td_class_ary = @{ $td_classes };
	foreach(0..$#ary) {
		my $x = $ary[$_];
		my $h = {cols=>1, rows=>1};
		$h->{class} = shift( @td_class_ary );
		if (substr($x,0,1) eq '*') {
			$h->{th}   = 1;
			$h->{data} = substr($x,1);
		} elsif ($x eq '<' && $#cols >= 0) {	# 左連結
			$h = $cols[$#cols];
			$h->{cols} ++; 
		} elsif (($x eq '~' || $x eq '^') && $#$rows >= 0 && $_ < $#{ $rows->[$#$rows]}) {	# 上連結
			$h = $rows->[$#$rows]->[$_];
			$h->{rows} ++;
		} else {
			$h->{data} = $x;
		}
		push(@cols, $h);
	}
	if ($#cols > 0) {
		foreach(reverse(0..($#cols-1))) {
			if ($cols[$_]->{data} eq '>') {	# 右連結
				$cols[$_] = $cols[$_+1];
				$cols[$_]->{cols} ++;
			}
		}
	}

	# trクラス指定
	my $class    = 'even';
	my $tr_count = ++ $self->{tr_count};
	if ($tr_count & 1) { $class='odd'; }
	$class .= $self->{tr_class};
	$self->{tr_class} = undef;
	push(@cols, $class);
	push(@$rows, \@cols);
	return undef;
	# return "\t<tr class=\"$class\">$line</tr>\n";
}

#---------------------------
# テーブルの出力
#---------------------------
sub table_output {
	my ($self, $out, $class) = @_;
	my $ROBJ = $self->{ROBJ};
	my $rows = $self->{table_rows};
	my $summary = $self->{table_summary};
	my $caption = $self->{table_caption};
	$self->{table_rows} = $self->{tr_class} = $self->{td_classes} = undef;
	$self->{table_summary} = $self->{table_caption} = undef;
	$self->{tr_count} = 0;
	if (!defined $rows) { return ; }

	# 下に連結？
	foreach my $row_num (reverse(0..($#$rows-1))) {
		my $cols = $rows->[$row_num];
		foreach(0..($#$cols-1)) {
			my $h = $cols->[$_];
			if ($h->{data} eq '_' && ref($rows->[$row_num+1]->[$_])) {
				$h = $rows->[$row_num]->[$_] = $rows->[$row_num+1]->[$_];
				$h->{rows}++;
			}
		}
	}

	# caption & summary
	$self->tag_syntax_escape($summary);		# 記法タグも escape
	$ROBJ->tag_escape($caption);
	if ($summary ne '') { $summary="<!-- summary=$summary -->"; }
	# 出力
	push(@$out, "<table$class>$summary\n");
	if ($caption ne '') { push(@$out, "<caption>$caption</caption>\n"); }
	my $thead_flag;
	if (1 < $#$rows) {
		# テーブルの行が２行以上あり、最初の行がすべて th ならば、
		# その部分を thead として認識する。
		my $cols=$rows->[0];
		$thead_flag = 1;
		foreach(@$cols) {
			if (ref($_) && ! $_->{th}) { $thead_flag=0; last; }
		}
	}
	
	if ($thead_flag) { push(@$out, "<thead>\n"); }
		    else { push(@$out, "<tbody>\n"); }
	while(@$rows) {
		my $cols = shift(@$rows);
		my $tr_class = pop(@$cols);
		my $line;
		my $th_only = 1;
		foreach(0..$#$cols) {
			my $h = $cols->[$_];
			if ($h->{output}) { next; }	# １度出力したものは出力しない
			# 出力
			$h->{output} = 1;
			my $at;
			if ($h->{cols} >1) { $at .= " colspan=\"$h->{cols}\""; }
			if ($h->{rows} >1) { $at .= " rowspan=\"$h->{rows}\""; }
			if ($h->{class})   { $at .= " class=\"$h->{class}\"";  }
			if ($h->{th}) {
				$line .= "<th$at>$h->{data}</th>";
			} else {
				$th_only = 0;
				$line .= "<td$at>$h->{data}</td>";
			}
		}
		if ($thead_flag && !$th_only) {
			push(@$out, "</thead><tbody>\n");
			$thead_flag = 0;
		}
		push(@$out, "\t<tr class=\"$tr_class\">$line</tr>\n");
	}
	push(@$out, "</tbody></table>\n");
}


#--------------------------------------------------------------------
# 「続きを読む（完全省略）」 - =====
#--------------------------------------------------------------------
sub super_more_read {
	my ($self, $line) = @_;
	if ($self->{more_read}) { return ; }
	$self->{more_read} = 1;
	my $seemore_msg = $self->{seemore_msg} || 'See More...';
	return <<HTML;
$self->{indent}<p class="seemore"><a class="seemore" href="$self->{thisurl}#$self->{now_anchor_name}">$self->{seemore_msg}</a></p><!--%SeeMore%-->
HTML
}

###############################################################################
# ■[03] 記法タグの処理
###############################################################################
sub replace_original_tag {
	my ($self, $lines) = @_;

	my $autolink = $self->{autolink};
	my @ary;
	foreach(@$lines) {
		if (ref($_)) { push(@ary, $_); next; }

		# 自由変数書き換え
		if ($_ =~ /^:::([A-Za-z]\w*)\s*=\s*(.*)/) {
			$self->{vars}->{$1} = $2;
			next;
		}
		# 内部変数書き換え
		if ($_ =~ /^::(\w+)=(.*)/ && $allow_override{$1}) {
			$self->{$1} = $2;
			next;
		}

		if ($autolink && $_ =~ /https?:|ftp:/) {
			$_ = $self->do_autolink( $_ );
		}

		# タグ処理
		$_ = $self->parse_tag( $_ );

		# 記法置き換えで行が空になった
		if ($_ eq '') { next; }

		push(@ary, $_);
	}

	return \@ary;
}

# markdowm.pm からも呼ばれる
sub do_autolink {
	my ($self, $line) = @_;
	my @ary;
	$line =~ s/(<\w(?:[^>"']|[=\s]".*?\"|[=\s]'.*?')*?>)/push(@ary, $1), "\x00$#ary\x00"/esg;
	$line =~ s!(\G|\n|[^\"\[:])(https?|ftp):(//[\w\./\#\@\?\&\~\=\+\-%\[\]:;,\!*]+)!
			my $x="$1\[$2:"; my $y=$3;
			$y =~ s/([\[\]:])/"&#" . ord($1) . ';'/eg;
			"$x$y]";
	       !eg;
	$line =~ s/\x00(\d+)\x00/$ary[$1]/sg;
	return $line;
}

#--------------------------------------------------------------------
# ○タグのパースと処理
#--------------------------------------------------------------------
sub parse_tag {
	my $self = shift;
	my $this = shift;
	my $post_process = shift;	# markdown記法で使用

	# [[ ]] タグを先行処理
	my $count=100;
	while ($count>0 && $this =~ /(.*?)\[\[(.*?\]*)\s?\]\](.*)/s) {
		# [[aa:[[bb:テキスト]]]] のとき bb タグを先に処理する
		my $x = rindex($2, '[[');
		my $p0  = $1 . ($x<0 ? '' : '[[' . substr($2,0,$x));	# tagより前
		my $cmd =       $x<0 ? $2 :        substr($2,$x+2);
		my $p1  = $3;	# tagより後ろ
		$this = $self->special_command( $cmd, {verb => 1} );
		$this =~ s/\[/&#91;/g;
		$this =~ s/\]/&#93;/g;
		$this =~ s/:/&#58;/g;
		$this = $p0 . $this . $p1;
		if ($post_process) { $this = &$post_process($this); }
		$count--;
	}
	
	# [ ] タグを処理
	while ($count>0 && $this =~ /(^|.*?[^\\])\[((?:\\\[|\\\]|[^\[\]])+)\](.*)/s) {
		my $p0 = $1;	# tagより前
		my $p1 = $3;	# tagより後ろ
		$this = $self->special_command( $2 );
		$this =~ s/\[/&#91;/g;
		$this =~ s/\]/&#93;/g;
		$this =~ s/:/&#58;/g;
		$this = $p0 . $this . $p1;
		if ($post_process) { $this = &$post_process($this); }
		$count--;
	}
	return $this;
}

#--------------------------------------------------------------------
# ○コマンドの処理
#--------------------------------------------------------------------
sub special_command {
	my $self     = shift;
	my $cmd_line = shift;
	my $opt  = shift || {};
	my $tags = $self->{tags};
	my $orig = $cmd_line;

	# 特殊コマンド処理
	# [&icon-name] → [icon:icon-name]
	$cmd_line =~ s/^&(\w+)$/icon:$1/g;
	# [&http://youtube.com/] → [filter:http://youtube.com]
	$cmd_line =~ s/^&(.+)$/filter:$1/g;
	# [$name] → 自由変数nameの中身を出力
	if ($cmd_line =~ /^\$(.*)$/) {
		return $self->{vars}->{$1};
	}

	# cmd:arg1:arg2 ... のパース
	if (!$opt->{verb}) {
		$cmd_line =~ s/\\([\[\]])/$1/g;
		$cmd_line =~ s/\\:/\x00/g;
	}
	
	my @cmd = map { s/\x00/:/g; $_ } split(':', $cmd_line);
	my $cmd = shift(@cmd);
	while (exists $tags->{ "$cmd:$cmd[0]" } && @cmd) {	# 連結コマンド
		$cmd = $cmd . ':' . shift(@cmd);
	}

	if (exists $tags->{ $cmd }) {
		my $tag = $self->load_tag($cmd);
		# verb環境？
		if ($opt->{verb}) {
			@cmd = ( join(':', @cmd) );
		}
		# alias 処理
		my $real_cmd = $cmd;
		if ($tag->{alias}) {
			$real_cmd = $tag->{alias};
			$tag      = $self->load_tag($real_cmd);
		}
		# 引数指定あり？
		my $arg_cmd = $real_cmd . '##' . ($#cmd +1);
		if (exists $tags->{ $arg_cmd }) {
			$tag = $tags->{ $arg_cmd };
		} else {
			my $x = $#cmd + 1;
			$x=0;
			foreach(@cmd) {
				if ($_ =~ /[\x80-\xff]/) { last }
				if (substr($_,-1) eq ' ') {	# 最後がスペースの引数
					chop($_);
					last;
				}
				$x++;
			}
			my $arg_cmd = $real_cmd . '#' . $x;
			if (exists $tags->{ $arg_cmd }) { $tag = $tags->{ $arg_cmd }; }
		}

		# 置換処理呼び出し
		my $data   = $tag->{data};
		my $option = $self->load_tag("&$tag->{option}");	# 特殊オプション？

		if (ref($option)) {			# 特殊オプションによる置換
			return &$option($self, $tag, $cmd, \@cmd);
		} elsif (ref($data)) {		# CODE ref のときは指定の専用ルーチンコール
			return &$data($self, $tag, $cmd, \@cmd);
		} elsif($tag->{html}) {		# HTML置換タグ
			return $self->html_tag($tag, \@cmd);
		} elsif($data) {		# それ以外のときは汎用検索置換ルーチンへ
			return $self->search($tag, $cmd, \@cmd);
		}
	}
	# 未知のコマンド
	return $opt->{verb} ? "[[$orig]]" : "[$orig]";
}

sub load_tag {
	my $self = shift;
	my $cmd = shift;
	my $tag = $self->{tags}->{$cmd};
	if (ref($tag) eq 'CODE') { return $tag; }
	if ($tag->{plugin}) {
		$self->eval_load_plugin( $tag->{plugin} );
	}
	return $self->{tags}->{$cmd};
}

#------------------------------------------------------------------------------
# ●記法タグルーチン
#------------------------------------------------------------------------------
#--------------------------------------------------------------------
# ●htmlタグ置換
#--------------------------------------------------------------------
sub html_tag {
	my ($self, $tag, $ary) = @_;
	my ($name, $class) = split('\.', $tag->{html});
	if ($class ne '') { $class=" class=\"$class\""; }
	if (!@$ary) { return "<$name$class$tag->{attribute}></$name>"; }
	return "<$name$class$tag->{attribute}>" . join(':', @$ary) . "</$name>";
}

#--------------------------------------------------------------------
# ●汎用リンク置換（記法タグ）
#--------------------------------------------------------------------
sub search {
	my ($self, $tag, $cmd, $ary) = @_;
	my $ROBJ = $self->{ROBJ};

	# Query 構成
	my $code = $tag->{option};
	my $argc = $tag->{argc};
	my $url  = $tag->{data};

	my @argv = splice(@$ary, 0, $argc);
	if ($#$ary>=0 && $tag->{replace_html}) {
		# タグそのままのとき、最後を連結。
		# 2引数 [color:red:xxx:yyy] を "red" / "xxx:yyy" にする
		$argv[$argc-1] .= ':' . join(':', @$ary);
		@$ary = ();
	}

	# リンク置換
	my $name = join(':', @argv);
	$url = $self->replace_link($url, \@argv, $argc, $code);

	# タグそのまま
	if ($tag->{replace_html}) {
		$url =~ s/&quot;/"/g;
		return $url;
	}

	# リンク構成
	my $class = $self->make_attr($ary, $tag, 'http');
	   $name  = $self->make_name($ary, $name);

	return "<a href=\"$url\"$class>$name</a>";
}

#--------------------------------------------------------------------
# ●オプションタグ（出力されないタグ）
#--------------------------------------------------------------------
sub option {
	my ($self, $tag, $cmd, $ary) = @_;
	$self->{options}->{$cmd} = $ary;
	return '';
}

#--------------------------------------------------------------------
# ●link文字列の置換処理
#--------------------------------------------------------------------
sub replace_link {
	my $self = shift;
	my ($url, $ary, $argc, $code) = @_;
	my $ROBJ = $self->{ROBJ};
	my $rep  = $self->{vars};

	my @argv = splice(@$ary, 0, $argc);
	unshift(@argv,  $ROBJ->{Basepath});
	$url =~ s/\#(\d)/$argv[$1]/g;			# 文字コード変換前

	if ($code eq 'ASCII' || $code !~ /[A-Z]/) { $code=''; }
	my $jcode = $code ? $ROBJ->load_codepm() : undef;

	foreach(@argv) {
		if ($jcode) { $jcode->from_to(\$_, $ROBJ->{System_coding}, $code); }
		$self->encode_uricom($_);
	}
	$url =~ s/\$(\d)/$argv[$1]/g;		# 文字コード変換後
	$url =~ s/\$\{(\w+)\}/$rep->{$1}/g;	# 任意データ置換
	# 全引数置換
	shift(@argv);
	my $all = join(':', @argv);
	$url =~ s/\$\$/$all/g;
	return $url;
}

#--------------------------------------------------------------------
# ●replace_varsのみの実装
#--------------------------------------------------------------------
sub replace_vars {
	my $self = shift;
	my $url = shift;
	my $h = $self->{vars};
	$url =~ s/\$\{(\w+)\}/$h->{$1}/g;	# 任意データ置換
	return $url;
}

###############################################################################
# ■[03] 段落/改行処理
###############################################################################
sub paragraph_processing {
	my ($self, $lines) = @_;

	my $br_mode  = $self->{br_mode};
	my $p_mode   = $self->{p_mode};
	my $p_class  = $self->{p_class};
	my $ls_mode  = $self->{ls_mode};		# 行間処理モード
	my $indent   = $self->{indent};
	$self->{footnote_no} = 0;

	# p class処理
	$p_class =~ s/[^\w\-]//g;
	if ($p_class ne '') { $p_class = " class=\"$p_class\""; }

	# 処理前準備
	my ($prev, $next, $this, $prev_f, $this_f, $next_f);
	push(@$lines, "\x01");

	my @ary;
	my @footnote;
	$self->{footnote} = \@footnote;
	$self->{note_buf} = {};
	my $in_paragraph  = 0;
	foreach(@$lines) {
		# モジュールのみの行を段落処理しないでdivブロック化する
		if ($_ =~ /^\s*(?:<module [^>]*>\s*)+\s*$/) {
		 	$_ = "<div class=\"module\">$_</div>\n";
		}

		# 行送り措置
		$prev = $this; $prev_f = $this_f;
		$this = $next; $this_f = $next_f;
		$next = $_;    $next_f = 0;

		my $f = substr($_,-1);
		if ($f eq "\x01") { $next_f= 1; chop($next); }	# インデント抑止
		if ($f eq "\n")   { $next_f=10;  }
		if (ref($_))      { $next_f=256; }
		if (!defined $this) { next; }

		# 前後のどちらかがコマンド
		my $flag = $prev_f + $next_f;

		# Section(H3) の終わり
		if (ref($this) && $this->{section_end}) {
			$self->output_footnote(\@ary, \@footnote);
			@footnote = ();
			next;
		}
		# 空行？
		if (ref($this)) {
			my $null_lines = $this->{null_lines};
			if (! $ls_mode) {	# 行間処理をしないモード
				push(@ary, "$indent\n" x $null_lines);
				next;
			}
			if ($flag || $p_mode) { $null_lines--; } 
			push(@ary, "$indent<br>\n" x $null_lines);
			next;
		}
		# 注釈処理 ((xxxx))
		$this =~ s/\(\((.*?)\)\)/ $self->footnote($1) /eg;

		# 段落処理
		if ($this_f==1) { push(@ary, $this);          next; } # インデントなし
		if ($this_f)    { push(@ary, "$indent$this"); next; } # 処理済み行はインデントのみ
		if ($p_mode==1) { push(@ary, "$indent<p$p_class>$this</p>\n"); next; } # １行＝１段落
		if (! $p_mode)  {	# 段落処理なし
			if ($br_mode) { push(@ary, "$indent$this<br>\n"); }    # 改行処理
				else  { push(@ary, "$indent$this\n");     }
			next;
		}
		if ($p_mode==2) {	# 空行で段落処理
			my $head = '';
			if (! $in_paragraph) { $head="$indent<p$p_class>"; $in_paragraph=1; } # 段落の始まり 
			elsif ($br_mode)     { $head="$indent";   }                           # 改行処理モード
			push(@ary, "$head$this");
			if ($next_f) {		# ここで段落の終わり
				push(@ary, "</p>\n");
				$in_paragraph=0;
				next;
			}
			if ($br_mode) { push(@ary, "<br>\n"); }	# 改行処理
			next;
		}
	}

	return \@ary;
}

#--------------------------------------------------------------------
# ○脚注表記
#--------------------------------------------------------------------
sub footnote {
	my ($self, $note) = @_;
	my $footnote = $self->{footnote};

	# 同じ内容は、同じfootnoteを参照する
	my $number;
	my $name;
	my $name_base = $self->{footnote_basename} || "$self->{unique_linkname}n";
	my $note_buf = $self->{note_buf};
	if (exists $note_buf->{$note}) {	# 同じ内容注釈がある
		$number = $note_buf->{$note};
		$name     = "$name_base$number";
	} else {
		$note_buf->{$note} = $number = (++ $self->{footnote_no});
		$name     = "$name_base$number";
		push(@$footnote, <<HTML);
	<p class="footnote"><a href="$self->{thisurl}#fnt-$name" id="fn-$name">*$number</a> : $note</p>
HTML
	}
	$self->tag_delete($note);
	$note =~ s/"/&quot;/g;

	return "<span class=\"footnote\"><a title=\"$note\" href=\"$self->{thisurl}#fn-$name\" id=\"fnt-$name\">*$number</a></span>";
}

#--------------------------------------------------------------------
# ○脚注表記の出力
#--------------------------------------------------------------------
sub output_footnote {
	my ($self, $out, $footnote) = @_;
	my $indent = $self->{indent};
	if (@$footnote) {
		push(@$out, "$indent<footer>\n");
		foreach(@$footnote) {
			push(@$out, "$indent$_");
		}
		push(@$out, "$indent</footer>\n");
	}
}

###############################################################################
# ■[99] ポストプロセス
###############################################################################
sub post_process {
	my ($self, $r_data) = @_;

	# 目次
	while ($$r_data =~ m|<toc>(.*?)</toc>|) {
		my %h;
		my $thisurl = $self->{thisurl};
		foreach(split(':', $1)) {
			if ($_ =~ /^(\w+)=(.*)$/) {
				$h{$1} = $2;
				next;
			}
			$h{$_}=1;
		}
		$h{anchor} ||= $self->{toc_anchor};

		my $class="toc";
		if ($h{none} || $h{anchor}) { $class .= " none"; }
		if ($h{class} ne '') { $class .= " $h{class}"; }

		my $sec_format = sub { "<a href=\"$thisurl#$_->{name}\">$_->{title}</a>" };
		if ($h{anchor}) {
			$sec_format = sub { "<span class=\"sanchor\">$_->{anchor}</span><a href=\"$thisurl#$_->{name}\">$_->{title}</a>" };
		}

		# 項目をリスト作成
		my @out;
		my $level = ($h{level} eq '') ? $self->{toc_level} : int($h{level});
		my $func;
		$func = sub {
			my $out = shift;
			my $ary = shift;
			my $t   = shift;
			if (length($t) > $level) { return; }
			$t .= "\t";

			push(@$out, "<ul class=\"$class\">\n");
			foreach(@$ary) {
				my $subs = $_->{children};
				if (!$subs || !@$subs) {
					push(@$out, "$t<li>" . &$sec_format() . "</li>\n");
					next;
				}
				push(@$out, "$t<li>" . &$sec_format() . "\n");
				&$func($out, $subs, $t);
				push(@$out, "</li>\n");
			}
			push(@$out, "</ul>");
		};
		&$func(\@out, $self->{sections});
		my $str = join('', @out);
		$$r_data =~ s|<toc>(.*?)</toc>|$str|;
	}
}

###############################################################################
# ■内部サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●タグ/記法記号のエスケープ（エンコード）
#------------------------------------------------------------------------------
# 【注意】ここを修正したら、ブロック記法中のエスケープ部も修正すること！
sub tag_syntax_escape {
	my $self=shift;
	foreach(@_) {
		$_ =~ s/&/&amp;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
		$_ =~ s/"/&quot;/g;		# _~^* は table 記法用
		$_ =~ s/([\[\]\{\}\(\)\|:_~^*])/'&#' . ord($1) . ';'/eg;
	}
}

#------------------------------------------------------------------------------
# ●タグの除去
#------------------------------------------------------------------------------
sub tag_delete {
	my $self=shift;
	foreach(@_) {
		$_ =~ s/<\/.*?>//sg;
		$_ =~ s/<\w([^>"']|[=\s]".*?"|[=\s]'.*?')*?>//sg;
	}
}

#------------------------------------------------------------------------------
# ●エスケープした文字の復元
#------------------------------------------------------------------------------
sub un_escape {
	my $self=shift;
	foreach(@_) {
		$_ =~ s/&#(40|41|91|93|123|125|124|58|42|94|126|61|43|45);/chr($1)/eg;
	}
	return $_[0];
}

#------------------------------------------------------------------------------
# ●class/id表記の分離と解析
#------------------------------------------------------------------------------
sub parse_class_id {
	my $self=shift;
	my $str=shift;
	my $id;
	$str =~ s/(?:^|\s)[Ii][Dd]=([\w\-]+)/$id=$1,""/e;
	$str =~ s/^\s*(.*?)\s*$/$1/;
	$str =~ s/[^\w\-: ]//g;
	$str =~ s/\s+/ /g;
	
	my $r;
	$r  = ($str ne '' ? " class=\"$str\"" : '');
	$r .= ($id  ne '' ? " id=\"$id\"" : '');
	return $r;
}

#------------------------------------------------------------------------------
# ●URIエンコード
#------------------------------------------------------------------------------
sub encode_uri {
	my $self=shift;
	return $self->{ROBJ}->encode_uri(@_);
}
sub encode_uricom {
	my $self=shift;
	return $self->{ROBJ}->encode_uricom(@_);
}

#------------------------------------------------------------------------------
# ●class/target/titleの設定
#------------------------------------------------------------------------------
sub make_attr {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($ary, $tag, $type) = @_;

	# target/class/rel 設定, type未定義のとき初期値なし(mailto:等)
	my $target = $self->{"${type}_target"};
	my $class  = $self->{"${type}_class"};
	my $data   = $self->{"${type}_data"};
	my $title  = $tag->{title} || $tag->{name};
	while(1) {
		my $x = $ary->[0];
		if (substr($x, 0, 7) eq 'target=') { $target = substr(shift(@$ary), 7); next; }
		if (substr($x, 0, 6) eq 'title=' ) { $title  = substr(shift(@$ary), 6); next; }
		if (substr($x, 0, 6) eq 'class=' ) { $class  = substr(shift(@$ary), 6); next; }
		if (substr($x, 0, 5) eq 'data='  ) { $data   = substr(shift(@$ary), 4); next; }
		last;
	}
	$target =~ s/[^\w\-]//g;
	$class  =~ s/[^\w\s:\-]//g;
	$data   =~ s/%k/$self->{unique_linkname}/g;
	$ROBJ->tag_escape($title);

	if ($class ne '' && $tag->{class} ne '') { $class =" $class"; }
	if ($class ne '' || $tag->{class} ne '') { $class =" class=\"$tag->{class}$class\""; }
	if ($title  ne '') { $class .=" title=\"$title\""; }
	if ($target ne '') { $class .=" target=\"$target\""; }
	if ($data ne '') {	# data: aaa=bbb, ccc=ddd
		my @ary = split(/\s*,\s*/, $data);
		foreach(@ary) {
			if ($_ !~ /^([A-Za-z][\w\-]*)=(.*)$/) { next; }
			my $n = $1;
			my $v = $2;
			$ROBJ->tag_escape($v);
			$class .=" data-$n=\"$v\"";
		}
	}

	# 属性文字列を返す
	return $class;
}
#--------------------------------------
# name の設定
#--------------------------------------
sub make_name {
	my $self=shift;
	my ($ary, $name) = @_;
	my $x = join(':', @$ary);
	return ($x eq '' ?  $name : $x);
}

1;
