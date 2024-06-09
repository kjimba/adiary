use strict;
#-------------------------------------------------------------------------------
# adiary_4.pm (C)nabe@abk
#-------------------------------------------------------------------------------
# ・プラグイン管理関連
# ・デザイン関連
# ・テーマ関連
#-------------------------------------------------------------------------------
use SatsukiApp::adiary ();
use SatsukiApp::adiary_2 ();
use SatsukiApp::adiary_3 ();
package SatsukiApp::adiary;
################################################################################
# ■ユーザー定義記法タグ、ユーザーCSSの設定
################################################################################
#-------------------------------------------------------------------------------
# ●ユーザー定義タグファイルのロード
#-------------------------------------------------------------------------------
sub load_usertag {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $file = $self->{blog_dir} . 'usertag.txt';
	if (!-e $file) { $file = $self->{default_usertag_file}; }
	return join('', @{ $ROBJ->fread_lines($file) });
}

#-------------------------------------------------------------------------------
# ●ユーザー定義タグの保存
#-------------------------------------------------------------------------------
sub save_usertag {
	my ($self, $tag_txt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	if (! $self->{allow_edit}) { $ROBJ->message('Operation not permitted'); return 5; }

	my $r = $ROBJ->fwrite_lines( $self->{blog_dir} . 'usertag.txt', $tag_txt );
	if ($r) {
		$ROBJ->message('Save failed');
		return 1;
	}
	return 0;
}

#-------------------------------------------------------------------------------
# ●ユーザーCSSファイルのロード
#-------------------------------------------------------------------------------
sub load_usercss {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $file = $self->dynamic_css_file('_usercss');
	if (!-r $file) { $file = $self->{default_usercss_file}; }
	return join('', @{ $ROBJ->fread_lines($file) });
}

#-------------------------------------------------------------------------------
# ●ユーザーCSSの保存
#-------------------------------------------------------------------------------
sub save_usercss {
	my ($self, $css_txt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	if (! $self->{allow_edit}) { $ROBJ->message('Operation not permitted'); return 5; }

	if ($css_txt =~ /^\s*$/s) {
		return $self->delete_dynamic_css( '_usercss' );
	}

	if (!$self->{trust_mode}) {
		# 危険文字の除去
		while($css_txt =~ /behavior/i) {
			$css_txt =~ s/behavior//ig;
		}
	}

	return $self->save_dynamic_css( '_usercss', $css_txt );
}

################################################################################
# ■動的CSS 管理機構
################################################################################
#-------------------------------------------------------------------------------
# ●CSSの保存
#-------------------------------------------------------------------------------
sub save_dynamic_css {
	my $self = shift;
	my $name = shift;
	my $css  = shift;
	my $ROBJ = $self->{ROBJ};
	if ($name =~ /[^\w\-,]/ || $name =~ /^\s*$/g) { return 1; }
	if (ref($css)) { $css = join('', @$css); }

	if ($css =~ /^\s$/s) {	# 中身がからっぽ
		$css = '';	# 0byte でファイルを置いておかないと矛盾が起こる
	}

	# 中身があるかチェック / usercssを除く
	if ($name !~ /^_/) {
		$css = $self->check_css_content($css);
	}

	my $dir = $self->dynamic_css_dir();
	$ROBJ->mkdir($dir);
	my $file = $self->dynamic_css_file($name);
	$ROBJ->fwrite_lines($file, $css);

	return $self->update_dynamic_css();
}

#-------------------------------------------------------------------------------
# ●CSSの削除
#-------------------------------------------------------------------------------
sub delete_dynamic_css {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	if ($name =~ /[^\w\-,]/ || $name =~ /^\s*$/g) { return 1; }

	my $file = $self->dynamic_css_file($name);
	$ROBJ->file_delete( $file );

	return $self->update_dynamic_css();
}

#-------------------------------------------------------------------------------
# ●動的CSSをまとめて1つのCSSに出力
#-------------------------------------------------------------------------------
sub update_dynamic_css {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir = $self->dynamic_css_dir();
	my $files = $ROBJ->search_files($dir, {ext => '.css'});

	# 名前順ソート。ただし _ で始まるファイルを最後に処理する
	$files = [ sort {
			my ($x,$y) = ($a,$b);
			$x =~ tr/a-z/A-Z/;
			$y =~ tr/a-z/A-Z/;
			$x cmp $y;
	} @$files ];

	my @ary;
	foreach(@$files) {
		my $css = join('', @{ $ROBJ->fread_lines("$dir$_") });
		$css = $self->check_css_content($css);
		if (!$css) { next; }		# 中身のないファイルを無視
		push(@ary, "\n/* from '$_' */\n\n");
		push(@ary, $css);
	}

	my $file = $self->{blogpub_dir} . 'dynamic.css';
	$ROBJ->fwrite_lines($file, \@ary);
	return 0;
}

#-------------------------------------------------------------------------------
# ●動的CSSの存在確認
#-------------------------------------------------------------------------------
sub check_dynamic_css {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	my $file = $self->dynamic_css_file( $name );
	return (-r $file) ? 1 : 0;
}

#-------------------------------------------------------------------------------
# ●動的CSS保管領域
#-------------------------------------------------------------------------------
sub dynamic_css_dir {
	my $self = shift;
	return $self->{blogpub_dir} . 'css.d/';
}
sub dynamic_css_file {
	my $self = shift;
	my $name = shift;
	return $self->dynamic_css_dir() . $name . '-d.css';
}

#-------------------------------------------------------------------------------
# ●CSSが中身があるか確認する
#-------------------------------------------------------------------------------
sub check_css_content {
	my $self = shift;
	my $css  = shift;
	my @str;
	$css =~ s|\x01||g;
	$css =~ s|/\*(.*?)\*/||sg;				# コメント除去
	$css =~ s/((['"])(?:\\.|.)*?\2)/
		push(@str, $1), "\x01[$#str]"/seg;		# 文字列を置換
	$css =~ s|[\w\-\[\]=,\.*>~:\s\(\)\#]*\{\s*\}||sg;	# 中身のない定義を除去
	if ($css =~ /^\s*$/s) {					# 残りが空白だけ
		return '';
	}
	$css =~ s/\s*\n+/\n/g;
	$css =~ s/^\n//;
	$css =~ s/\x01\[(\d+)\]/$str[$1]/g;			# 文字列を復元
	return $css;
}
################################################################################
# ■プラグインの設定
################################################################################
#-------------------------------------------------------------------------------
# ●plugin/以下のプラグイン情報取得
#-------------------------------------------------------------------------------
sub load_modules_info {
	my $self = shift;
	return $self->load_plugins_info(1);
}
sub load_plugins_info {
	my $self = shift;
	my $modf = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir   = $self->{plugin_dir};
	my $files = $ROBJ->search_files($dir, {dir_only => 1});
	my @ary;
	foreach( sort @$files ) {
		my $f = ($_ =~ /^de[smhacf]_/);		# デザインモジュール？
		if (!$modf && $f || $modf && !$f) { next; }

		# load
		my $pi = $self->load_plugin_info($_, $dir) || next;
		push(@ary, $pi);
		$self->check_plugin_env($pi);
	}
	return \@ary;
}

sub load_plugins_dat {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	return $ROBJ->fread_hash_cached( $self->{blog_dir} . 'plugins.dat', {NoError => 1} );
}

#-------------------------------------------------------------------------------
# ●プラグインがインストール中か調べる
#-------------------------------------------------------------------------------
sub check_installed_plugin {
	my $self = shift;
	my $name = shift;
	my $pd = $self->load_plugins_dat();
	return $pd->{$name};
}

#-------------------------------------------------------------------------------
# ●必要な環境やライブラリが揃ってるか調べる
#-------------------------------------------------------------------------------
sub check_plugin_env {
	my $self = shift;
	my $pi   = shift;
	my @libs = split(/\n/, $pi->{require});
	my $err=0;
	my @missing;
	foreach(@libs) {
		if (!$_) { next; }
		my $file = $_;
		$file =~ s|::|/|g;
		eval { require "$file.pm"; };
		if ($@) {
			$err++;
			push(@missing, $_);
		}
	}
	$pi->{missing} = @missing ? \@missing : undef;
}

#-------------------------------------------------------------------------------
# ●ひとつのプラグイン情報取得
#-------------------------------------------------------------------------------
sub load_module_info {
	return &load_plugin_info(@_);
}
sub load_plugin_info {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $name = shift;
	my $dir  = shift || $self->{plugin_dir};

	# キャッシュ
	my $cache = $self->{"_plugin_info_cache"} ||= {};
	if ($cache->{"$dir$name"}) { return $cache->{"$dir$name"}; }

	if (substr($name,-1) eq '/') { chop($name); }
	my $n = $self->plugin_name_check( $name );
	if (!$n) { return; }		# プラグイン名, $name=プラグインのインストール名

	my $h = $ROBJ->fread_hash_no_error( "$dir$n/plugin.info" );
	if (!$h || !%$h) { return; }
	$h->{readme} = -r "$dir$n/README.txt" ? 'README.txt' : undef;
	$h->{name} = $name;

	# sample.html/module.htmlが存在する
	if (-r "$dir$n/sample.html") {
		$h->{sample_html} ||= join('', @{ $ROBJ->fread_lines("$dir$n/sample.html") });
	}
	if (-r "$dir$n/module.html") {
		$h->{module_html} ||= join('', @{ $ROBJ->fread_lines("$dir$n/module.html") });
	}

	# <@this>, <@id>の置換
	my $id = $h->{module_id} || $self->plugin_name_id( $name, 1 );
	$h->{files}  =~ s/<\@this>/$name/g;
	$h->{events} =~ s/<\@this>/$name/g;
	$h->{files}  =~ s/\r\n/\n/g;
	$h->{events} =~ s/\r\n/\n/g;
	my @ary = grep { /^module\w*_html$/ } keys(%$h);
	push(@ary, 'sample_html');
	foreach(@ary) {
		$h->{$_} =~ s/<\@this>/$name/g;
		$h->{$_} =~ s/<\@id>/$id/g;
	}

	# タグの除去
	foreach(keys(%$h)) {
		if (substr($_,-4) eq 'html') { next; }
		$ROBJ->tag_escape($h->{$_});
	}

	# setting.html
	$h->{module_setting} = -r "$dir$n/setting.html";
	# デザイン設定ファイル
	$h->{css_setting}    = -r "$dir$n/css_setting.html";

	#---------------------------------------------------
	# 表示用イベント情報
	#---------------------------------------------------
	$h->{events_display} = $h->{events};
	if ($h->{events} ne '' ) {
		$h->{events}  =~ s/\r?\n?$/\n/;
	}

	# 動的CSSファイル
	my $dcss = $h->{module_dcss} = -r "$dir$n/module-d.css";
	if ($dcss) {
		$h->{events} .= <<DCSS_EVENT;
INSTALL=skel/_sub/module_css_generate
SETTING=skel/_sub/module_css_generate
PRIVATE_MODE_ON=skel/_sub/module_css_generate
PRIVATE_MODE_OFF=skel/_sub/module_css_generate
UNINSTALL=skel/_sub/module_css_delete
DCSS_EVENT
	}

	# イベントの末尾改行除去
	chomp($h->{events});

	# キャッシュ
	$cache->{"$dir$name"} = $h;

	return $h;
}

#-------------------------------------------------------------------------------
# ●使用するプラグイン設定を保存する
#-------------------------------------------------------------------------------
sub save_use_modules {
	my $self = shift;
	return $self->save_use_plugins($_[0], 1);
}
sub save_use_plugins {
	my $self = shift;
	my $form = shift;
	my $modf = shift;
	my $blog = $self->{blog};
	my $ROBJ = $self->{ROBJ};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	my $pd      = $self->load_plugins_dat();
	my $plugins = $self->load_plugins_info($modf);
	my $ary = $plugins;
	my %common;
	if ($modf) {
		# モジュールの場合
		# ※1つのモジュールを複数配置することがあるので、その対策。
		# 　その場合 $name="des_name,1", $n="des_name" となる
		my %pl = map { $_->{name} => $_ } @$plugins;
		my %names;
		$ary = [];
		foreach(keys(%$form)) {
			my $n = $self->plugin_name_check( $_ );
			if (!$n || !$pl{$n}) { next; }
			if ($n eq $_) {
				$names{$_}=1;
				next;
			}

			# エイリアスを保存
			my %h = %{ $pl{$n} };
			$h{name} = $_;
			push(@$ary, \%h);
			$common{$n} = $form->{$n} ||= $form->{$_};
		}
		foreach(keys(%common)) {
			delete $names{$_};
		}
		unshift(@$ary, map { $pl{$_} } keys(%names));
		foreach(keys(%common)) {
			# エイリアスのコモン名のinstall/uninstall設定
			if ($form->{$_}) {
				unshift(@$ary, $pl{$_});	# install
			} else {
				push(@$ary, $pl{$_});		# unisntall
			}
		}
	}
	my $err = 0;
	my $flag= 0;
	my %fail;
	foreach(@$ary) {
		my $name = $_->{name};
		my $inst = $form->{$name} ? 1 : 0;
		if ($_->{adiary_version} > $self->{VERSION})  { $inst=0; }	# 非対応バージョン
		if ($_->{trust_mode} && !$self->{trust_mode}) { $inst=0; }	# trust_mode専用
		if ($pd->{$name} == $inst) { next; }				# 変化なし

		my $prev_install;

		# 状態変化あり
		my $func = $inst ? 'plugin_install' : 'plugin_uninstall';
		my $msg  = $inst ? 'Install'        : 'Uninstall';

		# $cname:コモン名、$name:インストール名
		my $cname = $self->plugin_name_check( $name );

		# アンインストールイベント
		if (!$inst) {
			my $r = $self->call_event("UNINSTALL:$name");
			if ($r) {
				$ROBJ->message("[plugin:%s] Uninstall event failed", $name);
				# アンインストールイベント処理に失敗しても、
				# アンインストール処理は継続させる。
				# $fail{$cname}=1;
				# next;
			}
		}

		# 多重インストール処理
		if ($cname ne $name) {
			if ($inst) {
				# install
				if ($fail{$cname}) { $fail{$name}=1; next; }

				$pd->{"$name"} = 1;
				$pd->{"$name:events"} = $_->{events};

				# install event
				my $h = {};
				$self->set_event_info($h, $pd);
				$self->do_call_event("INSTALL:$name", $h);

				# common名でのイベント登録を削除
				delete $pd->{"$cname:events"};
			} else {
				# uninstall
				delete $pd->{"$name"};
				delete $pd->{"$name:events"};
			}
			$flag=1;
			next;
		}

		# install/uninstall 実行
		my $r = $fail{$name} ? 100 : $self->$func( $pd, $_ );
		$err += $r;
		if (!$r && $inst && !$common{$name}) {
			my $h = {};
			$self->set_event_info($h, $pd);
			$r = $self->do_call_event("INSTALL:$name", $h);
			if ($r) {
				$self->plugin_uninstall($pd, $_);
			}
		}
		if ($r) {
			$fail{$name}=1;
			$ROBJ->message("[plugin:%s] $msg failed", $name);
			next;
		}
		$flag=1;
		if (! $self->{stop_plugin_install_msg}) {
			$ROBJ->message("[plugin:%s] $msg success", $name);
		}
	}
	# 状態変更があった？
	if ($flag) {
		# プラグイン情報の保存
		$ROBJ->fwrite_hash($self->{blog_dir} . 'plugins.dat', $pd);

		# イベント情報の登録
		$self->set_event_info($self->{blog}, $pd);

		# イベント
		$self->call_event('PLUGIN_STATE_CHANGE');
	}
	return wantarray ? (0, \%fail) : 0;
}

#-------------------------------------------------------------------------------
# ●プラグインのインストール
#-------------------------------------------------------------------------------
sub plugin_install {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($pd, $plugin) = @_;

	my $files  = $plugin->{files};
	my $events = $plugin->{events};
	my $name   = $plugin->{name};			# インストール名
	my $n      = $self->plugin_name_check( $name );	# プラグイン名

	# イベントチェック
	my @ary = split(/\n/, $events);
	foreach(@ary) {
		if ($_ !~ /_VIEW/) { next; }
		my ($evt, $file) = split(/=/, $_, 2);
		if ($file =~ m|^skel/|) { next; }

		$ROBJ->error('[plugin:%s] %s event error (skeleton only) : %s', $n, $evt, $file);
		return 1000;
	}

	# 必要なディレクトリの作成
	$ROBJ->mkdir( $self->{blog_dir} . 'func/' );
	$ROBJ->mkdir( $self->{blog_dir} . 'skel/' );
	$ROBJ->mkdir( $self->{blogpub_dir} . 'js/'    );
	$ROBJ->mkdir( $self->{blogpub_dir} . 'css/'   );
	$ROBJ->mkdir( $self->{blogpub_dir} . 'css.d/' );

	# インストールディレクトリ
	my $plg_dir  = $self->plugin_name_dir($n);	# plugin/ : 読み込み用
	my $copy = $self->{plugin_symlink} ? 'file_symlink' : 'file_copy';

	# ファイルのインストール
	my $err=0;
	my $cssd;
	my @copy_files;
	foreach(split("\n",$files)) {
		# 親ディレクトリ参照などの防止
		$ROBJ->clean_path($_);

		# タイプ別のフィルタ
		my $des = $self->get_plugin_install_dir( $_ );
		if ($des && substr($_,0,5) eq 'skel/') {
			$self->mkdir_with_filepath( $des, $_ );
		}

		if (!$des) {
			$ROBJ->error("[plugin:%s] Not allow directory name : %s", $name, $_);
			$err++;
			next;
		}
		if (! -r "$plg_dir$_") {
			$ROBJ->error("[plugin:%s] Original file not exists : %s", $name, $_);
			$err++;
			next;
		}

		# 既にファイルが存在している場合はエラー
		$des .= $_;
		if (-e $des) {
			$ROBJ->error("[plugin:%s] File already exists : %s", $name, $des);
			$err++;
			next;
		}

		# ファイルをコピーしてインストール
		if ($err) { next; }	# エラーがあればコピーはしない
		my $r = $ROBJ->$copy( "$plg_dir$_", $des);
		if ($r || !-e $des) {
			$err++;
			next;
		}

		# インストールしたファイルを記録
		push(@copy_files, $_);
	}
	if ($cssd) { $self->update_dynamic_css(); }

	if ($err) {
		foreach(@copy_files) {
			$ROBJ->file_delete( $self->get_plugin_install_dir($_) . $_ );
		}
		return $err;
	}

	# 情報の登録
	$pd->{$name} = 1;
	$pd->{"$name:version"} = $plugin->{version};
	$pd->{"$name:files"}   = join("\n", @copy_files);
	$pd->{"$name:events"}  = $plugin->{events};

	return 0;
}

sub get_plugin_install_dir() {
	my $self = shift;
	my $file = shift;
	my ($dir, $file) = $self->split_equal($_, '/');

	if ($dir eq 'func' || $dir eq 'skel' || $dir eq 'etc') {
		return $self->{blog_dir};
	}
	if ($dir eq 'js' || $dir eq 'css' || $dir eq 'css.d') {
		return $self->{blogpub_dir};
	}
	return ;
}

#-------------------------------------------------------------------------------
# ●プラグインのアンインストール
#-------------------------------------------------------------------------------
sub plugin_uninstall {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($pd, $plugin) = @_;

	my $name = ref($plugin) ? $plugin->{name} : $plugin;
	my $files = $pd->{"$name:files"};
	my $err=0;
	my $cssd=0;
	foreach(split("\n", $files)) {
		my $file = $self->get_plugin_install_dir($_) . $_;
		my $r = $ROBJ->file_delete( $file );
		if (!$r) {	# 削除失敗でもファイルがなければ良しとする
			$r = !-x $file;
		}
		if ($r) {	# 成功
			if ($_ =~ m|/css\.d/|) { $cssd=1; }
			next;
		}
		$err++;
		$ROBJ->error("[plugin:%s] File delete failed : %s", $name, $file);
	}
	if ($cssd && !$plugin->{module_dcss}) {
		$self->update_dynamic_css();
	}
	if ($err) { return $err; }

	# 情報の削除
	my $len = length("$name:");
	foreach(keys(%$pd)) {
		if (substr($_,0,$len) ne "$name:") { next; }
		delete $pd->{$_};
	}
	delete $pd->{$name};
	return 0;
}

#-------------------------------------------------------------------------------
# ●パスを辿ってmkdir
#-------------------------------------------------------------------------------
sub mkdir_with_filepath {
	my $self = shift;
	my ($dir, $file) = @_;
	my $ROBJ = $self->{ROBJ};

	my @ary = split('/', $file);
	pop(@ary);	# ファイル名を捨てる
	while(@ary) {
		$dir .= shift(@ary) . '/';
		$ROBJ->mkdir( $dir );
	}
}

#-------------------------------------------------------------------------------
# ●プラグイン情報からイベントを登録
#-------------------------------------------------------------------------------
my %SPECIAL_EVENTS = (	# イベント名が「INSTALL:plugin_name」のようになるもの
	INSTALL => 1,
	UNINSTALL => 1,
	SETTING => 1
);
sub set_event_info {
	my $self = shift;
	my ($blog, $pd) = @_;

	my @plugins = sort(grep { index($_, ':')<0 } keys(%$pd));
	my %evt;
	my %js_evt;
	foreach my $name (@plugins) {
		foreach( split("\n", $pd->{"$name:events"})) {
			my ($k,$v) = $self->split_equal($_);
			if ($k eq '') { next; }
			if ($SPECIAL_EVENTS{$k}) {
				$k .= ":$name";
			}
			# JSイベントは多重呼び出ししない
			if ($k =~ /^JS/) {
				my $cname = $self->plugin_name_check( $name );
				$js_evt{$k}->{$cname} = $v;
				next;
			}
			$evt{$k} ||= [];
			push(@{ $evt{$k} }, "$name=$v");
		}
	}

	# JSイベントを重複を避けて登録
	foreach my $k (keys(%js_evt)) {
		$evt{$k} = [];
		my $h = $js_evt{$k};
		foreach(keys(%$h)) {
			push(@{ $evt{$k} }, "$_=$h->{$_}");
		}
	}

	# 登録済イベントを削除
	foreach(keys(%$blog)) {
		if (substr($_,0,6) ne 'event:') { next; }
		delete $blog->{$_};
	}

	# イベントの登録
	foreach(keys(%evt)) {
		$blog->{"event:$_"} = join("\n", @{ $evt{$_} });
	}
	$self->update_blogset($blog);

	# viewイベント用html生成
	$self->update_view_event($blog);

	return 0;
}

#-------------------------------------------------------------------------------
# ●プラグインviewイベントの更新
#-------------------------------------------------------------------------------
sub update_view_event {
	my $self = shift;
	my $blog = shift;
	my $ROBJ = $self->{ROBJ};

	my @evt = qw(
		VIEW_MAIN
		VIEW_ARTICLE
	);
	foreach my $name (@evt) {
		my $file = $name;
		$file =~ tr/A-Z/a-z/;
		$file = $self->{blog_dir} . 'skel/_' . $file . '.html';

		# イベントが存在しない
		my $evt = $blog->{"event:$name"};
		if (!$evt) {
			$ROBJ->file_delete( $file );
			next;
		}

		my @html = ("<\@6>\n");
		foreach(split(/\n/, $evt)) {
			my ($e,$f) = split(/=/, $_, 2);
			push(@html, "<@> '$f' from '$e' plugin\n");
			push(@html, @{ $ROBJ->fread_lines($self->{blog_dir} . $f) });
		}
		$ROBJ->fwrite_lines($file, \@html);
	}
}

#-------------------------------------------------------------------------------
# ●プラグインの設定を保存
#-------------------------------------------------------------------------------
sub save_plugin_setting {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $name = $form->{module_name};

	my $mode = $form->{setting_mode};
	if ($mode ne 'css') { $mode = ''; }
	if ($mode ne '') { $mode .= '_'; }

	my $n = $self->plugin_name_check($name);	# $n = プラグイン名
	if (!$n) { return 1; }

	my $dir = $self->{plugin_dir} . $n;
	my $ret;
	my $pm = "$dir/${mode}validator.pm";
	if (-r $pm) {
		my $func = $self->load_plugin_function( $pm, $pm );
		$ret = &$func($self, $form, $name);
	} else {
		$ret = $ROBJ->_call("$dir/${mode}validator.html", $form, $name);
	}
	if (ref($ret) ne 'HASH') { return; }

	$self->update_plgset($name, $ret);
	$self->call_event("SETTING:$name");
	$self->call_event('PLUGIN_SETTING', $name);
	return 0;
}

#-------------------------------------------------------------------------------
# ●プラグイン設定のリセット
#-------------------------------------------------------------------------------
sub reset_plugin_setting {
	my $self = shift;
	my $name = shift;
	my $pd   = $self->load_plugins_dat();

	# uninstall
	if ($pd->{$name}) {
		$self->call_event("UNINSTALL:$name");
	}

	# delete setting
	my $set = $self->{blog};
	foreach(keys(%$set)) {
		if ($_ !~ /^p:([\w\-]+(?:,\d+)?)/ || $1 ne $name) { next; }
		$self->update_blogset($set, $_, undef);
	}

	# reinstall
	if ($pd->{$name}) {
		$self->call_event("INSTALL:$name");
	}
	return 0;
}

#-------------------------------------------------------------------------------
# ●プラグイン名のチェックとalias番号の分離
#-------------------------------------------------------------------------------
# plugin_num in adiary_2.pm
sub plugin_name_check {
	my $self = shift;
	return ($_[0] =~ /^([A-Za-z][\w\-]*)(?:,\d+)?$/) ? $1 : undef;
}
sub plugin_name_id {
	my $self = shift;
	my $name = shift;
	my $stop = shift;
	if ($name !~ /,/) {	# 多重インストールモジュールではない
		if ($stop) { return ''; }
		my $h = $self->load_plugin_info($name) || {};
		return $h->{module_id};
	}
	$name =~ tr/_,/--/;
	return $name;
}
sub plugin_name_dir {
	my $self = shift;
	my $name = $self->plugin_name_check(shift);
	return $self->{plugin_dir} . "$name/";
}

#-------------------------------------------------------------------------------
# ●プラグインのための画像アップロード処理（一括）
#-------------------------------------------------------------------------------
sub plugin_upload_images {
	my $self = shift;
	my $ret  = shift;
	my $name = shift;	# プラグイン名
	my $form = shift;
	my $ary  = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir = $self->plugin_image_dir();
	foreach(@$ary) {
		if (!ref($form->{$_})) { next; }
		if (! $form->{$_}->{size}) { next; }		# サイズ0は無視
		my $r = $self->upload_image_for_plugin($name, $_, $form->{$_});
		if ($r) { next; }

		# アップロード成功
		my $file = $ret->{$_} = $form->{$_}->{name};

		# サイズ取得
		my $img = $self->load_image_magick();
		if (!$img) { next; }
		eval {
			$img->Read( "$dir$file" );
			$img = $img->[0];
			$ret->{"${_}_w"} = $img->Get('width');
			$ret->{"${_}_h"} = $img->Get('height');
		};
	}
}

#-------------------------------------------------------------------------------
# ●プラグインのための画像アップロード
#-------------------------------------------------------------------------------
sub upload_image_for_plugin {
	my $self = shift;
	my $pname= shift;	# プラグイン名
	my $fname= shift;	# ファイル名
	my $file = shift;
	my $ROBJ = $self->{ROBJ};
	if (!$file) {
		$ROBJ->form_error('file', "File data error.");
		return -1;
	}
	if ($file->{name} =~ /(\.\w+)$/) {
		$fname .= $1;
	}
	if (!$self->is_image($fname)) {
		$ROBJ->form_error('file', "File is not image : %s", $file->{name});
		return -1;
	}

	# アップロード
	my $dir = $self->plugin_image_dir();
	$self->init_image_dir();
	$ROBJ->mkdir( $dir );

	$file->{name}      = $pname . '-' . $fname;
	$file->{overwrite} = 1;
	return $self->do_upload( $dir, $file );
}

#-------------------------------------------------------------------------------
# ●プラグインのための画像ファイル名取得
#-------------------------------------------------------------------------------
sub void_plugin_images {
	my $self = shift;
	my $h    = shift;
	my $form = shift;
	foreach(keys(%$form)) {
		if ($_ !~ /^(\w+)_void$/) { next; }
		if (! $form->{$_}) { next; }
		my $n = $1;
		$h->{$n} = undef;
		$h->{"${n}_w"} = undef;
		$h->{"${n}_h"} = undef;
	}
}

#-------------------------------------------------------------------------------
sub plugin_image_dir {
	my $self = shift;
	return $self->image_folder_to_dir( '@system/' ) . shift;
}

################################################################################
# ■デザインモジュールの設定
################################################################################
#-------------------------------------------------------------------------------
# ●デザインの保存
#-------------------------------------------------------------------------------
sub save_design {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	my @side_a = @{$form->{side_a_ary}  || []};
	my @side_b = @{$form->{side_b_ary}  || []};
	my @main_a = @{$form->{main_a_ary}  || []};
	my @main_b = @{$form->{main_b_ary}  || []};
	my @header = @{$form->{header_ary}  || []};
	my @art_h  = @{$form->{art_h_ary}   || []};
	my @art_f  = @{$form->{art_f_ary}   || []};
	my @com    = @{$form->{com_ary}     || []};
	my @mart_h = @{$form->{mart_h_ary}  || []};
	my @mart_f = @{$form->{mart_f_ary}  || []};
	my @between= @{$form->{between_ary} || []};
	my %save   = map {$_ => 1} @{$form->{save_ary} || []};

	my %use_f  = map {$_ => 1} (@side_a,@side_b,@main_a,@main_b,@header,@art_h,@art_f,@com,@mart_h,@mart_f,@between);
	my $pd = $self->load_plugins_dat();
	my @multi;
	foreach(keys(%$pd)) {	# 現在のinstall状態確認
		if (index($_,':')>0) { next; }
		if ($pd->{$_} && !$use_f{$_}) { $use_f{$_}=0; }	# uninstall

		# マルチインストールモジュールの抽出
		my $n = $self->plugin_name_check($_);
		if ($_ eq $n) { next; }
		push(@multi, $n);
	}
	# マルチインストールモジュールは common名 に対する操作を無視させる
	foreach(@multi) {
		delete $use_f{$_};
	}

	# プラグイン状況を保存
	my ($ret, $fail) = $self->save_use_modules(\%use_f);
	if ($ret) { return $ret; }	# error

	# そのブログ専用のスケルトンとして保存する準備
	my $dir = $self->{blog_dir} . 'skel/';
	$ROBJ->mkdir($dir);
	my $ret = 0;

	# 書き込み前にスケルトンを消す
	$self->delete_design_skeleton( $dir );

	#-----------------------------------------------------------------------
	# _sidebar.html を生成
	#-----------------------------------------------------------------------
	if (!%save || $save{_sidebar}) {
		my $file = '_sidebar';
		my $h = $self->parse_original_skeleton($file);
		my @html;
		push(@html, @{$h->{HEADER} || []});
		foreach(@side_a) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		push(@html, @{$h->{SEPARATOR} || []});
		foreach(@side_b) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		push(@html, @{$h->{FOOTER} || []});

		my $r = $ROBJ->fwrite_lines("$dir$file.html", \@html);
		if ($r) {
			$ret++;
			$ROBJ->message('Design save failed : %s', "$file.html");
		}
	}

	#-----------------------------------------------------------------------
	# _header.html を生成
	#-----------------------------------------------------------------------
	if (!%save || $save{_header}) {
		my $file = '_header';
		my $h = $self->parse_original_skeleton($file);
		my @html;
		push(@html, @{$h->{HEADER} || []});
		foreach(@header) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		push(@html, @{$h->{FOOTER} || []});

		my $r = $ROBJ->fwrite_lines("$dir$file.html", \@html);
		if ($r) {
			$ret++;
			$ROBJ->message('Design save failed : %s', "$file.html");
		}
	}

	#-----------------------------------------------------------------------
	# _article.html を生成
	#-----------------------------------------------------------------------
	if (!%save || $save{_article}) {
		my $file = '_article';
		my $h = $self->parse_original_skeleton($file);

		my @html;
		push(@html, @{$h->{HEADER} || []});
		foreach(@main_a) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		#---記事表示部------------------------------
		push(@html, @{$h->{ARTICLE_TOP} || []});
		foreach(@art_h) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		push(@html, @{$h->{ARTICLE_MIDDLE} || []});
		foreach(@art_f) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		push(@html, @{$h->{ARTICLE_BOTTOM} || []});
		push(@html, @{$h->{COMMENT_TOP}    || []});
		foreach(@com) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		push(@html, @{$h->{COMMENT_BOTTOM} || []});
		#-------------------------------------------
		foreach(@main_b) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		push(@html, @{$h->{FOOTER} || []});

		my $r = $ROBJ->fwrite_lines("$dir$file.html", \@html);
		if ($r) {
			$ret++;
			$ROBJ->message('Design save failed : %s', "$file.html");
		}
	}

	#-----------------------------------------------------------------------
	# _main.html を生成
	#-----------------------------------------------------------------------
	if (!%save || $save{_main}) {
		my $file = '_main';
		my $h = $self->parse_original_skeleton($file);

		my @html;
		push(@html, @{$h->{HEADER} || []});
		foreach(@main_a) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		#---記事と記事の間--------------------------
		push(@html, @{$h->{BETWEEN_TOP} || []});
		foreach(@between) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		push(@html, @{$h->{BETWEEN_BOTTOM} || []});
		#---記事表示部------------------------------
		push(@html, @{$h->{ARTICLE_TOP} || []});
		foreach(@mart_h) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		push(@html, @{$h->{ARTICLE_MIDDLE} || []});
		foreach(@mart_f) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		push(@html, @{$h->{ARTICLE_BOTTOM} || []});
		#-------------------------------------------
		foreach(@main_b) {
			if ($fail->{$_}) { next; }
			push(@html, $self->load_module_html($_, $file) . "\n");
		}
		push(@html, @{$h->{FOOTER} || []});

		my $r = $ROBJ->fwrite_lines("$dir$file.html", \@html);
		if ($r) {
			$ret++;
			$ROBJ->message('Design save failed : %s', "$file.html");
		}
	}

	#-----------------------------------------------------------------------
	# デザイン情報を保管（再構築時用）
	#-----------------------------------------------------------------------
	$self->update_design_info({
		version => 7,
		side_a => join("\n", @side_a),
		side_b => join("\n", @side_b),
		main_a => join("\n", @main_a),
		main_b => join("\n", @main_b),
		header => join("\n", @header),
		art_h  => join("\n", @art_h),
		art_f  => join("\n", @art_f),
		com    => join("\n", @com),
		mart_h => join("\n", @mart_h),
		mart_f => join("\n", @mart_f),
		between=> join("\n", @between),
		save   => join("\n", keys(%save))
	});	# ※reinstall_design_plugins() と対応させること！
		# 　項目追加時は version の数値を増加させる

	# イベント
	$self->call_event('EDIT_DESIGN');

	return $ret;
}
#-------------------------------------------------------------------------------
# ●オリジナルデザインのパース
#-------------------------------------------------------------------------------
sub parse_original_skeleton {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};

	# ユーザーレベルスケルトンを無効化して読み込む
	my $lines = $ROBJ->fread_skeleton( $name, $self->{theme_skeleton_level} );

	# セパレーター探し
	my %h;
	my %in;
	foreach(@$lines) {
		if ($_ =~ /^<\@>\$PASTE=(.*)/s) {
			$_ = $1;
		}
		if ($_ =~ /^<\@>\$(\w+)\$/) {
			$in{$1} = 1;
			$h{$1} = [];
			next;
		}
		if ($_ =~ /^<\@>\$(\w+):END\$/i) {
			delete $in{$1};
			next;
		}
		foreach my $k (keys(%in)) {
			push(@{ $h{$k} }, $_);
		}
	}
	return \%h;
}

#-------------------------------------------------------------------------------
# ●モジュールHTMLの生成
#-------------------------------------------------------------------------------
sub load_module_html {
	my $self = shift;
	my $name = shift;
	my $target = shift;	# _article, _main 等が入る
	my $ROBJ = $self->{ROBJ};

	# trust_mode check
	my $info = $self->load_plugin_info($name) || {};
	if ($info->{trust_mode} && !$self->{trust_mode}) {
		return '';
	}

	# generatorの有無はファイルの存在で確認
	my $dir = $self->plugin_name_dir( $name );
	my $pm  = $dir . 'html_generator.pm';
	if (! -r $pm) {
		return $info->{"module${target}_html"} || $info->{"module_html"};
	}

	my $func = $self->load_plugin_function( $pm, $pm );
	if (ref($func) ne 'CODE') {
		return ;
	}

	my $ret;
	eval {
		$ret = &$func($self, $name, $target);
	};
	if ($@ || !defined $ret) {
		$ROBJ->error("[plugin:%s] Module's html generate failed : %s", $name, $@);
		return '';
	}
	return $ret;
}

#-------------------------------------------------------------------------------
# ●モジュールHTMLのロードと実行
#-------------------------------------------------------------------------------
sub load_and_call_module_html {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	# モジュールHTMLのロードが許可されているか？
	my $info = $self->load_plugin_info($name);
	if (!$info->{load_module_html_in_edit}) { return; }

	# インストールファイルがあるときはinstallされているか確認
	if ($info->{files}) {
		my $pd = $self->load_plugins_dat();
		if (!$pd->{$name}) { return; }
	}

	my $html = $self->load_module_html( $name );
	if (!$html) { return; }

	# ファイル展開して呼び出す
	my $file = "$self->{blog_dir}_call_module_html-$name.tmp";
	$ROBJ->fwrite_lines( $file, $html );
	my $ret = $ROBJ->_call( $file );
	$ROBJ->file_delete( $file );
	return $ret;
}

#-------------------------------------------------------------------------------
# ●デザインの初期化
#-------------------------------------------------------------------------------
sub reset_design {
	my $self = shift;
	my $opt  = shift;
	my $ROBJ = $self->{ROBJ};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	my %reset;
	my $pd = $ROBJ->fread_hash_cached( $self->{blog_dir} . 'plugins.dat', {NoError => 1} );
	foreach(keys(%$pd)) {
		if (index($_, ':') > 0) { next; }
		$reset{$_}=0;	# uninstall
	}
	my $ret = $self->save_use_modules(\%reset);

	# 生成スケルトンを消す
	$self->delete_design_skeleton($self->{blog_dir} . 'skel/');

	# インストール情報を消す
	$self->save_design_info({});

	# 個別の設定もすべて消す
	if ($opt->{all}) {
		my $blog = $self->{blog};
		foreach(keys(%$blog)) {
			if ($_ !~ /^p:de\w_/) { next; }
			delete $blog->{$_};
		}
		$self->update_blogset($blog);
	}

	if ($opt->{load_design}) {
		$self->load_default_design();
	} elsif(! $opt->{no_event}) {
		$self->call_event('EDIT_DESIGN');
	}

	return 0;
}

#-------------------------------------------------------------------------------
# ●デフォルトデザインのロード
#-------------------------------------------------------------------------------
sub load_default_design {
	my $self = shift;
	my $id   = shift;
	my $ROBJ = $self->{ROBJ};

	my $blogid = $self->{blogid};
	if (!$id && !$blogid) { return -1; }
	if ($id && $id ne $blogid) {
		my $r = $self->set_and_select_blog($id);
		if (!$r) { return -1; }
	}

	my $h = $self->parse_design_dat( $ROBJ->fread_hash( $self->{default_design_file} ) );
	$self->save_design( $h );

	return 0;
}

#-------------------------------------------------------------------------------
# ●デザイン詳細で生成するスケルトン消去
#-------------------------------------------------------------------------------
sub delete_design_skeleton {
	my $self = shift;
	my $dir  = shift;
	my $ROBJ = $self->{ROBJ};
	$ROBJ->file_delete($dir . '_header.html');
	$ROBJ->file_delete($dir . '_sidebar.html');
	$ROBJ->file_delete($dir . '_article.html');
	$ROBJ->file_delete($dir . '_main.html');
}


################################################################################
# ■プラグインの動的CSS処理
################################################################################
#-------------------------------------------------------------------------------
# ●モジュールCSSの生成
#-------------------------------------------------------------------------------
sub generate_module_css {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir = $self->plugin_name_dir( $name );
	my $css = $dir . "module-d.css";
	if (! -r $css) { return; }

	# 動的生成CSSがある？
	my $id = $self->plugin_name_id( $name );
	return $ROBJ->_call($css, $name, $id);
}

#-------------------------------------------------------------------------------
# ●モジュールCSSの保存
#-------------------------------------------------------------------------------
sub generate_and_save_module_css {
	my $self = shift;
	my $name = shift;
	my $css  = $self->generate_module_css( $name );
	return $self->save_dynamic_css($name, $css);
}

# 削除
sub delete_module_css {
	&delete_dynamic_css(@_);
}

################################################################################
# ■テーマ選択
################################################################################
#-------------------------------------------------------------------------------
# ●テンプレートリストのロード
#-------------------------------------------------------------------------------
sub load_templates {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	# テンプレートdir
	my $theme_dir  = $self->{theme_dir};
	my $dirs = $ROBJ->search_files($theme_dir, { dir_only => 1 });
	$dirs = [ grep(/^[A-Za-z]/, @$dirs) ];

	# satsuki で始まるテンプレートを優先的に表示
	foreach(@$dirs) { chop($_); }
	$dirs  = [ sort {( (!index($b,'satsuki')) <=> (!index($a,'satsuki')) ) || $a cmp $b} @$dirs ];
	foreach(@$dirs) { $_ .= '/'; }
	return $dirs;
}

#-------------------------------------------------------------------------------
# ●テーマリストの作成
#-------------------------------------------------------------------------------
sub load_themes {
	my ($self, $template) = @_;
	my $ROBJ = $self->{ROBJ};

	# テンプレートdir選択
	$template =~ s/[^\w\-]//g;
	if ($template eq '') { return; }
	my $dir = "$self->{theme_dir}$template/";

	# テーマリストの取得
	my @files = sort map { chop($_);$_ } @{ $ROBJ->search_files($dir, { dir_only => 1 }) };
	my @ary;
	foreach(@files) {
		if (substr($_,0,1) eq '_') { next; }	# 先頭 _ を無視
		my %h;
		$h{name}   = $_;
		$h{readme} = (-r "$dir$_/README" || -r "$dir$_/README.txt") ? 1 : 0;
		push(@ary, \%h);
	}
	return \@ary;
}

#-------------------------------------------------------------------------------
# ●テーマリストの作成
#-------------------------------------------------------------------------------
sub save_theme {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	my $theme = $form->{theme};
	if ($theme !~ m|^[\w-]+/[\w-]+/?$|) {
		return 1;
	}

	# テーマ保存
	$self->update_cur_blogset('theme', $theme);
	$self->update_cur_blogset('theme_custom', '');
	$self->update_cur_blogset('sysmode_notheme', $form->{sysmode_notheme_flg});

	# テーマカスタマイズ情報の保存
	if (!$form->{custom}) { return 0; }
	my ($c,$opt,$css) = $self->load_theme_colors( $theme );
	if (!$css) { return 0; }
	my $file = $self->get_theme_custom_css($theme, 1);

	my %col;
	my %opt;
	my $diff;
	foreach(keys(%$opt)) {
		if ($_ !~ /^(.*)-default$/) { next; }
		# デフォルトを含む
		$diff=1;
		if ($form->{$1} ne '') { next; }
		$css .= "\n/* \$$1= */";
	}
	foreach(keys(%$form)) {
		if ($_ =~ /^option\d*$/ && $form->{$_} ne '') {
			$opt{$_} = $form->{$_};
			$diff=1;
			next;
		}
		if ($_ !~ /^c_(\w+)/) { next; }
		my $name = $1;
		my $val = $form->{$_};
		if ($val !~ /(#[0-9A-Fa-f]{6})/) { next; }
		$col{$name} = $1;
		if ($c->{$name} ne $col{$name}) { $diff=1; }
	}
	if (!$diff) {	# カスタマイズしてない
		$ROBJ->file_delete( $file );
		return 0;
	}

	# CSS書き換え
	my $ary = $self->css_rewrite($css, \%col, \%opt);
	$ROBJ->fwrite_lines($file, $ary);

	# カスタマイズ情報の保存
	$self->update_cur_blogset('theme_custom', $file);

	# イベント
	$self->call_event('EDIT_THEME');

	return 0;
}

# remake_theme_custom_css から呼ばれる
sub css_rewrite {
	my $self = shift;
	my $css  = shift;
	my $col  = shift || {};
	my $opt  = shift || {};
	my $dir  = $self->{ROBJ}->{Basepath} . $self->{theme_dir};

	my @ary = split(/\n/, $css);
	my $in_opt;
	my $opt_sel;
	my $theme;
	foreach(@ary) {
		$_ .= "\n";
		if ($_ =~ m|\$theme=([\w\-]+/[\w\-]+)|) {
			$theme=$1;
		}
		if ($in_opt || $_ =~ /\$(option\d*)=([^\s]+)/) {
			if (!$in_opt) {
				$in_opt  = 1;
				$opt_sel = $opt->{$1} eq $2;
				$_ = $opt_sel ? "/* \$$1=$2 */\n" : '';
			} elsif ($_ =~ m|(.*?)\s*\*/|) {
				$in_opt = 0;
				$_ = $1;
				$_ = ($_ =~ /^(.*[;}])/) ? "$1\n" : '';
			}
			if (!$opt_sel) { $_ = ''; }

			# オプション内に画像ファイルを含む
			$_ =~ s!url\s*\(\s*(['"])([^'"]+)\1\s*\)!
				my $q = $1;
				my $file = $2;
				if ($file =~ m|^(?:\./)*[\w-]+(?:\.[\w-]+)*$|) {
					$file = $dir . $theme . '/' . $file;
				}
				"url($q$file$q)";
			!ieg;
		}
		if ($_ !~ /\$c=\s*(\w+)/) { next; }
		my $name = $1;
		$_ =~ s/#[0-9A-Fa-f]+/$col->{$name}/g;

		# rgba() の場合
		my $c = $col->{$name};
		my $rgba = hex(substr($c,1,2)) . ',' . hex(substr($c,3,2)) . ',' . hex(substr($c,5,2));
		$_ =~ s/rgba\(\d+,\d+,\d+/rgba($rgba/g;
	}
	return \@ary;
}

#-------------------------------------------------------------------------------
# ●テーマの色カスタム情報ロード
#-------------------------------------------------------------------------------
sub load_theme_info {
	my ($self, $theme, $append) = @_;
	if (!defined $append) { $append = '-cst'; }
	my $ROBJ = $self->{ROBJ};
	if ($theme !~ m|^([\w-]+)/([\w-]+)/?$|) {
		return 1;
	}
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	# テーマ色情報のロード
	my ($col, $opt, $css) = $self->load_theme_colors($theme);
	if (!$css) { return ($col, $opt); }

	# カスタマイズ情報のロード
	my $file = $self->get_theme_custom_css($theme);
	if (-r $file) {
		my $lines = $ROBJ->fread_lines( $file );
		foreach(@$lines) {
			if ($_ =~ /\$(option\d*)=(.+)/) {
				$opt->{"$1$append"} = $2;
				$opt->{"$1$append"} =~ s|\s*\*/$||;
				next;
			}
			if ($_ !~ /(#[0-9A-Fa-f]+).*\$c=\s*(\w+)/) { next; }
			$col->{"$2$append"} = $1;
		}
	}
	return ($col, $opt, $css);
}

#-------------------------------------------------------------------------------
# ●テーマの色情報ロード
#-------------------------------------------------------------------------------
sub load_theme_colors {
	my ($self, $theme, $rec) = @_;
	my $ROBJ = $self->{ROBJ};

	my $lines;
	my $template;
	my $name;
	if (ref($theme)) {
		$lines = $theme;
		$rec = 1;	# 他ファイル参照無効
	} else {
		if ($theme !~ m|^([\w-]+)/([\w-]+)/?$|) {
			return 1;
		}
		$name = $theme;
		$template = $1;
		$theme = $2;
		$lines = $ROBJ->fread_lines( "$self->{theme_dir}$template/$theme/$theme.css" );
	}

	my %col;
	my %opt;
	my $sel  = '';
	my $attr = '';
	my $in_com;
	my $in_opt;
	my $in_attr;
	my $in_prop;
	my @ary;		# 抽出部保存用
	my $line_c=0;
	my @line_flag;		# 抽出部記録用
	foreach(@$lines) {
		$line_c++;
		$_ =~ s/\r\n?/\n/;
		if (!$in_opt && $_ =~ /\$(option\d*):title=([^\s]+)/) {
			$opt{"$1-title"} = $2;
			next;
		}
		if ( $in_opt || $_ =~ /\$(option\d*)(:default)?=([^\s]+)/) {	# オプション中
			if (!$in_opt) {
				$in_opt=1;
				$opt{$1} ||= [];
				push(@{ $opt{$1} }, $3);
				if ($2) {
					$opt{"$1-cst"}     = $3;	# default value
					$opt{"$1-default"} = $3;	# default value
					$_ =~ s/(\$option\d*):default/$1/;
				}
			}
			if ($_ =~ m|\*/|) {
				$in_opt=0;
			}
			push(@ary, $_);
			$line_flag[$line_c] = 1;
			next;
		}
		if ($in_com) {	# コメント中
			if ($_ !~ m|\*/(.*)|) { next; }
			$_ = $1;
			$in_com = 0;
		}
		if (!$rec && $_ =~ /\$color_info\s*=\s*([\w\-]+)/) {	# /* $color_info = satsuki2 */
			# 色設定情報は、他ファイル参照
			return $self->load_theme_colors("$template/$1", 1);
		}
		if ($_ =~ /^\s*\@/) { next; }

		# /* $c=xxxcol=main */
		if ($_ =~ /\$c=\s*([\w]+)\s*=\s*([\s\w#:]*?)\s*\*\//) {
			if ($col{"$1-rel"} && $col{"$1-rel"} ne $2) {
				$col{"-err-$1"} = "[$line_c]$_<br> &emsp; $1=" . $col{"$1-rel"};
			}
			$col{"$1-rel"} = $2;
		}


		if ($_ =~ /\$c=\s*([\w]+)/) {	# /* $c=main */ 等の色名定義
			my $name = $1;
			$_ =~ s/#([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([^0-9A-Fa-f])/#$1$1$2$2$3$3$4/g;
			$_ =~ s/rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d\.]+)\s*\)/rgba($1,$2,$3,$4)/ig;

			if ($_ =~ /(#[0-9A-Fa-f]+)/ || $_ =~ /(rgba\(\d+,\d+,\d+,[\d\.]+\))/) {
				if ($col{$name} && $col{$name} ne $1) {
					$col{"-err-$name"} = "[$line_c]$_<br> &emsp; " . $col{$name};
				}
				$col{$name} = $1;
			}
			if (!$in_attr && $_ =~ /{.*}/) {
				push(@ary, $sel, $_);
				$sel='';
				next;
			}
			$in_prop=1;
		}
		if ($in_prop) {
			$line_flag[$line_c] = 1;

			# プロパティが終わってない
			$in_prop = ($_ !~ /[;}]/);

			# プロパティの開始まで戻る
			my $c = $line_c;
			my $x = $_;
			while ($x =~ s|/\*.*?\*/||sg, 
			  ($x !~ /[\w-]+[\s\n\r]*:/ && $c>1 && !$line_flag[$c-1])) {
				$_ = $lines->[$c-2] . $_;
				$x = $lines->[$c-2] . $x;
				$c--;
			}
			$attr .= $_;
			next;

		}

		# その行だけのコメントを除去
		$_ =~ s|\s*/\*.*?\*/[\t ]*||g;
		if ($_ =~ m|(.*?)/\*|) {	# コメント開始
			$_ = $1;
			$in_com = 1;
		}
		if ($_ =~ /^\s*\n?$/) { next; }	# 空行
		if ($_ =~ /}/) {
			if ($attr ne '') {
				push(@ary, $sel, $attr, $_);
			}
			$sel = $attr = '';
			$in_attr=0;
			next;
		}
		if ($in_attr) { next; }		# 一般属性値は無視
		if ($_ =~ /{/ && $_ !~ /{.*}/) {
			$in_attr=1;
		}
		# セレクタ
		$sel .= $_;
	}

	# 後処理
	if (@ary && $name) {
		# CSS内でオプション部に url(); を含む時に必要
		unshift(@ary, "/* \$theme=$name */\n");
	}
	my $css = join('',@ary);
	# border:	1px solid #ffffff; → border-color: #ffffff
	# border-left:	1px solid #ffffff; → border-left-color: #ffffff
	$css =~ s/(border[\w\-]*?)(?:-color)?[\s\r\n]*?:[^;}]*?(#[0-9A-Fa-f]+[^\n]*\$c=)/$1-color:\t$2/ig;

	return (\%col, \%opt, $css);
}

#-------------------------------------------------------------------------------
# ●テーマカスタムファイルの取得
#-------------------------------------------------------------------------------
sub get_theme_custom_css {
	my ($self, $theme, $mkdir) = @_;
	my $ROBJ = $self->{ROBJ};
	my $dir = $self->{blogpub_dir} . 'css/';
	$mkdir && $ROBJ->mkdir($dir);
	$theme =~ s|/|.|g;
	return $dir . $theme . '.css';
}

#-------------------------------------------------------------------------------
# ●印刷用テーマリスト
#-------------------------------------------------------------------------------
sub load_print_themes {
	my ($self, $template) = @_;
	my $ROBJ = $self->{ROBJ};

	# テンプレートdir選択
	$template =~ s/[^\w\-]//g;
	if ($template eq '') { return []; }
	my $dir = "$self->{theme_dir}$template/";

	# テーマリストの取得
	my @files = sort map { chop($_);$_ } @{ $ROBJ->search_files($dir, { dir_only => 1 }) };
	my @ary;
	foreach(@files) {
		if (substr($_,0,1) ne '_') { next; }	# 先頭 _ を無視
		push(@ary, $_);
	}
	return \@ary;
}

################################################################################
# ■デザイン情報の管理
################################################################################
#-------------------------------------------------------------------------------
# ●デザイン情報のロード
#-------------------------------------------------------------------------------
sub load_design_info {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	return $ROBJ->fread_hash_cached( $self->{blog_dir} . 'design.dat', {NoError => 1} );
}

#-------------------------------------------------------------------------------
# ●デザイン情報の保存
#-------------------------------------------------------------------------------
sub save_design_info {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	return $ROBJ->fwrite_hash( $self->{blog_dir} . 'design.dat', @_ );
}

#-------------------------------------------------------------------------------
# ●デザイン情報の更新
#-------------------------------------------------------------------------------
sub update_design_info {
	my $self = shift;
	my $h = $self->load_design_info();
	$self->update_hash( $h, @_ );
	return $self->save_design_info($h);
}

################################################################################
# ■スマホ画面の設定
################################################################################
# in adiary_2.pm
#	generate_spmenu
#	load_spmenu_info
#	parse_html_for_spmenu
#-------------------------------------------------------------------------------
# ●スマホメニュー要素ロード
#-------------------------------------------------------------------------------
sub load_spmenu_items {
	my $self = shift;
	my $check= shift;	# 存在確認のみ
	my $set = $self->{blog};
	if (!$set) { return; }

	my @ary;
	my %names;
	foreach(keys(%$set)) {
		if ($_ !~ /^p:([\w\,]+):html$/) { next; }
		my $name = $1;
		my $pi = $self->load_plugin_info($name);
		if (! $pi->{sphone_menu}) { next; }

		my $h = $self->parse_html_for_spmenu( $set->{$_} );

		if (!$h->{html}) { next; }
		# save
		if ($check) { return 1; }
		my $h = {
			title=> $h->{title},
			html => $h->{html},
			name => $name,
			pi   => $pi
		};
		push(@ary, $h);
		$names{$name}=$h;
	}
	if (!@ary) { return; }

	my $iary = $self->load_spmenu_info();
	my @iary = grep { $names{ $_->{name}} } @$iary;
	foreach(@iary) {
		my $title = $_->{title};
		$_ = $names{ $_->{name} };
		$_->{title} = $title;
		$_->{on}    = 1;
	}

	my %n = map { $_->{name} => 1 } @iary;
	@ary = grep { ! $n{ $_->{name} }} @ary;
	@ary = sort { $a->{name} cmp $b->{name} } @ary;

	push(@iary, @ary);
	return \@iary;
}

#-------------------------------------------------------------------------------
# ●スマホメニュー要素のセーブ
#-------------------------------------------------------------------------------
sub save_spmenu_items {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $ary = $form->{mod_ary} || [];
	my $info='';
	foreach(@$ary) {
		my $title = $form->{$_} || $_;
		$ROBJ->trim($title);
		$ROBJ->tag_escape($title);
		$info .= "$_=$title\n";
	}
	chomp($info);
	$self->update_cur_blogset('spmenu_info',  $info);

	# タイトル保存
	my $title = $form->{spmenu_title};
	$ROBJ->trim($title);
	$ROBJ->tag_escape($title);
	$self->update_cur_blogset('spmenu_title', $title);

	return $self->generate_spmenu();
}

#-------------------------------------------------------------------------------
# ●スマホメニュー要素のセーブ
#-------------------------------------------------------------------------------
sub save_spmenu_all_items {
	my $self = shift;
	my $blog = $self->{blog};

	my $ary  = $self->load_spmenu_items();
	my $info = '';
	foreach(@$ary) {
		my $title = $_->{title} || $_->{pi}->{title};
		$info .= "$_->{name}=$title\n";
	}
	chomp($info);
	$self->update_cur_blogset('spmenu_info_all', $info);

	return $info;
}

#-------------------------------------------------------------------------------
# ●スマホメニューの項目が消えていないか確認
#-------------------------------------------------------------------------------
sub check_spmenu_items {
	my $self = shift;
	my $blog = $self->{blog};

	my $ary = $self->load_spmenu_info();
	my $f;
	my $info='';
	foreach(@$ary) {
		my $n = $_->{name};
		if (!$blog->{"p:$n:html"}) {
			$f=1;
			next;
		}
		$info .= "$n=$_->{title}\n";
	}
	if ($f) {	# 消えているモジュールがある
		chomp($info);
		$self->update_cur_blogset('spmenu_info', $info);
	}
}

1;
