//############################################################################
// adiaryテーマカスタマイズ用JavaScript
//							(C)2015 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
'use strict';
//////////////////////////////////////////////////////////////////////////////
// ●初期設定
//////////////////////////////////////////////////////////////////////////////
$(function(){
	var body = $('#body');
	var form = $('#form');
	var iframe = $('#iframe');
	var if_css;
	var readme = $('#readme-button');

	var sel = $('#theme-select');
	var theme_query='';

//////////////////////////////////////////////////////////////////////////////
// ●iframeの自動リサイズ
//////////////////////////////////////////////////////////////////////////////
	function iframe_resize() {
		var h = body.height() - iframe.position().top;
		$('#debug-msg').html(body.height() + ' / ' + iframe.position().top);
		iframe.css('height', h);
	}
	iframe_resize();
	$(window).resize( iframe_resize );

//////////////////////////////////////////////////////////////////////////////
// ●テーマ変更時の処理
//////////////////////////////////////////////////////////////////////////////
sel.change(function(){
	var theme = sel.val();
	theme_query = '?theme&n=' + theme;
	iframe.attr('src', Vmyself + theme_query ); 
	var opt = sel.children(':selected');
	if (opt.data('readme')) {
		readme.data('url', Vmyself + '?design/theme_readme&name=' + theme);
		readme.removeAttr('disabled');
	} else {
		readme.attr('disabled', true);
	}
	// カスタマイズ機能の初期化
	init_custmize(theme);
});
sel.change();

//////////////////////////////////////////////////////////////////////////////
// ●iframe内ロード（CSS欄追加。リンク書き換え）
//////////////////////////////////////////////////////////////////////////////
iframe.on('load', function(){
	if_css = $('<style>').attr('type','text/css');
	iframe.contents().find('head').append(if_css);

	if (!theme_query) return;
	iframe.contents().find('a').each(function(idx,dom) {
		var obj = $(dom);
		var url = obj.attr('href');
		if (!url) return;
		if (url.substr(0,Vmyself.length) != Vmyself) {
			obj.attr('target', '_top');
			return;
		}
		var m;
		if (m = url.match(/(.*?)\?(&.*)/)) {
			url = m[1] + theme_query + m[2];
		} else if (0 < url.indexOf('?')) {
			// obj.attr('target', '_top');
			return;
		} else if (m = url.match(/(.*?)(#.*)/)) {
			url = m[1] + theme_query + m[2];
		} else {
			url += theme_query;
		}
		obj.attr('href', url);
	});	// contents
	
	if (css_text) update_css();
});
//############################################################################
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// ●カスタマイズ機能
//////////////////////////////////////////////////////////////////////////////
	var custom_form  = $('#custom-form');
	var custom_cols  = $('#custom-colors');
	var custom_detail= $('#custom-colors-detail');
	var detail_mode  = $('#detail-mode');

	var input_cols;
	var rel_col;
	var rel_pol;

	var cols;
	var css_text;

//////////////////////////////////////////////////////////////////////////////
// ●カスタマイズ情報のロード
//////////////////////////////////////////////////////////////////////////////
function init_custmize(name) {
  cols = undefined;
  css_text = '';
  $.ajax({
	url: Vmyself + '?design/theme_colors&name=' + name,
	dataType: 'json',
	success: function(data){
		if (data.error || !data._css_text)
			return custom_form_empty();
		// 値保存
		css_text = data._css_text;
		delete data['_css_text'];
		$('#custom-flag').val('1');

		// フォーム初期化
		init_custom_form(data);
	},
	error: custom_form_empty
  });
}
function custom_form_empty() {
	custom_form.hide();
	custom_cols.empty();
	custom_detail.empty();
	input_cols = [];
	iframe_resize();
	$('#custom-flag').val('');
}

//////////////////////////////////////////////////////////////////////////////
// ●カスタマイズフォーム設定
//////////////////////////////////////////////////////////////////////////////
function init_custom_form(data) {
	cols = [];

	// データの取り出しと並べ替え
	var priority = ['base', 'main', 'art', 'wiki', 'footnote', 'border'];
	function get_priority(name) {
		if (name.indexOf( 'fix' ) == 0) return 1000;
		for(var i=0; i<priority.length; i++)
			if (name.indexOf( priority[i] ) == 0) return i;
		return 999;
	}
	for(var k in data) {
		if (k.rsubstr(4) == '-cst') continue;
		if (k.rsubstr(4) == '-rel') continue;
		cols.push({name: k, val: data[k], priority: get_priority(k) });
	}
	cols = cols.sort(function(a, b) {
		if (a.priority < b.priority) return -1;
		if (a.priority > b.priority) return  1;
	        return (a.name < b.name) ? -1 : 1;
	});

	// フォームの生成
	custom_cols.empty();
	custom_detail.empty();
	input_cols = [];
	rel_col = [];
	rel_pol = [];
	for(var i=0; i<cols.length; i++) {
		var name = cols[i].name;
		var val  = cols[i].val;
		var cval = data[name+'-cst'] || val; // 初期値
		var rel  = data[name+'-rel'];	// 他に連動
		var msg  = name2msg(name);

		var span = $('<span>').addClass('color-box');
		span.text(msg);
		var inp = $('<input>').addClass('color-picker no-enter-submit').attr({
			type: 'text',
			id: 'inp-' + name,
			name: 'c_' + name,
			value: cval
		});
		inp.data('original', val);	// テーマ初期値
		inp.data('default', cval);	// 現在の設定値
		inp.change( function(evt){
			update_css();
			var obj = $(evt.target);
			obj.ColorPickerSetColor( obj.val() );
		});
		(function(){
			var iobj = inp;		// クロージャ
			var n = name;
			iobj.data('onChange', function(hsb, hex, rgb) {
				iobj.data('val', '#' + hex);
				relation_colors(n);
				update_css();
				iobj.removeData('val');
			});
		})();
		span.append(inp);
		input_cols.push(inp);
		if (rel) {
			rel_col[name] = rel;
			var p = exp_to_poland(rel);
			if (p)	rel_pol[name] = p;	// 連動色？
			else	show_error('#css-exp-error', {s: rel});
		}

		// 要素を追加
		var div = rel ? custom_detail : custom_cols;
		if (name.substr(0,3) == 'fix'
		 && name != 'fixbg' && name != 'fixartbg' && name != 'fixfont')
			div = custom_detail;
		div.append(span);
	}
	input_cols = $(input_cols);
	custom_form.show();
	iframe_resize();
}

//////////////////////////////////////////////////////////////////////////////
// ●値連動処理
//////////////////////////////////////////////////////////////////////////////
function relation_colors(name) {
	if (detail_mode.prop('checked')) return;
	for(var k in rel_pol) {
		var v = exec_poland( rel_pol[k] );
		if (!v) {
			show_error('#css-exp-error', {s: rel_col[k]});
			continue;
		}
		var obj = $('#inp-' + k);
		set_color(obj, v);
	}
}

//////////////////////////////////////////////////////////////////////////////
// ●カスタマイズフォーム設定
//////////////////////////////////////////////////////////////////////////////
function update_css() {
	var col = {};
	input_cols.each(function(idx,dom){
		var obj = $(dom);
		var val = obj.data('val') || obj.val();
		if (val.match(/#[0-9A-Fa-f]{3}/) || val.match(/#[0-9A-Fa-f]{6}/))
			col[ obj.attr('name').substr(2) ] = val;
	});
	var lines = css_text.split("\n");
	for(var i=0; i<lines.length; i++) {
		var x = lines[i];
		var ma = x.match(/\$c=(\w+)/);
		if (!ma) continue;
		lines[i] = x.replace(/#[0-9A-Fa-f]+/, col[ ma[1] ]);
	}
	var new_css = lines.join("\n");
	try {
		if_css.html( new_css );
	} catch(e) {
		// for IE8
		iframe.contents().find('head').append(if_css);
		if_css[0].styleSheet.cssText = new_css;
	}
}

//////////////////////////////////////////////////////////////////////////////
// ●リセット
//////////////////////////////////////////////////////////////////////////////
$('#btn-reset').click( function() {
	var col = {};
	input_cols.each(function(idx,dom){
		var obj = $(dom);
		set_color(obj, obj.data('default'));
	});
	update_css();
});

//////////////////////////////////////////////////////////////////////////////
// ●テーマ初期値リセット
//////////////////////////////////////////////////////////////////////////////
$('#btn-super-reset').click( function() {
	var col = {};
	input_cols.each(function(idx,dom){
		var obj = $(dom);
		set_color(obj, obj.data('original'));
	});
	update_css();
});


//////////////////////////////////////////////////////////////////////////////
// ●色を設定
//////////////////////////////////////////////////////////////////////////////
function set_color(obj, rgb) {
	obj.val( rgb );
	if (obj.ColorPickerSetColor) {
		var prev = obj.prev();
		if (prev.hasClass('colorbox'))
			prev.css('background-color', rgb);
		obj.ColorPickerSetColor( rgb );
	}
}

//////////////////////////////////////////////////////////////////////////////
// ●色一括変更機能
//////////////////////////////////////////////////////////////////////////////
var h_slider = $('#h-slider');
var s_slider = $('#s-slider');
var v_slider = $('#v-slider');
function change_hsv() {
	if (!if_css) return;
	var h = h_slider.slider( "value" );
	var s = s_slider.slider( "value" );
	var v = v_slider.slider( "value" );

	var cols = input_cols;
	for(var i=0; i<cols.length; i++) {
		var obj = $(cols[i]);
		var name=obj.attr('name');
		if (name.indexOf('c_fix') == 0) continue;

		var hsv = RGBtoHSV( obj.data('default') );
		if (!hsv) return;
		// 色変換
		hsv.h += h;
		hsv.s *= (s/255);
		hsv.v *= (v/255);
		var rgb = HSVtoRGB( hsv );
		set_color(obj, rgb);
	}
	update_css();
}
$('#h-slider, #s-slider, #v-slider').slider({
	range: "min",
	max: 255,
	value: 255,
	slide: change_hsv,
	change: change_hsv
});
h_slider.slider('option', 'max', 360);
h_slider.slider('value', 0);

//////////////////////////////////////////////////////////////////////////////
// ●RGBtoHSV
//////////////////////////////////////////////////////////////////////////////
function RGBtoHSV(str) {
	var ma = str.match(/#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})/);
	if (!ma) return ;

	var r = parseInt('0x' + ma[1]);
	var g = parseInt('0x' + ma[2]);
	var b = parseInt('0x' + ma[3]);

	if (r==0 && g==0 && b==0)
		return {h:0, s:0, v:0};

	// 最大値 = V
	var max = r;
	if (max<g) max=g;
	if (max<b) max=b;
	var v = max;

	// 最小値
	var min = r;
	var min_is = 'r';
	if (min > g) {
		min = g;
		min_is = 'g';
	}
	if (min > b) {
		min = b;
		min_is = 'b';
	}
	// S
	var s = (max-min)*255/max;
	// h
	var h;
	if (max == min) h=0;
	else if (min_is == 'b')
		h = 60*(g-r)/(max-min) + 60;
	else if (min_is == 'r')
		h = 60*(b-g)/(max-min) + 180;
	else if (min_is == 'g')
		h = 60*(r-b)/(max-min) + 300;
	if (h<0)   h+=360;
	if (h>360) h-=360;

	return { h: h, s: s, v: v };
}

//////////////////////////////////////////////////////////////////////////////
// ●HSVtoRGB
//////////////////////////////////////////////////////////////////////////////
function HSVtoRGB( hsv ) {
	var max = hsv.v;
	var min = max - (hsv.s*max/255);

	var r;
	var g;
	var b;
	var h = hsv.h;
	if (h<0)   h+=360;
	if (h>360) h-=360;
	if (h<60) {
		r = max;
		g = (h/60) * (max-min) + min;
		b = min;
	} else if (h<120) {
		r = ((120-h)/60) * (max-min) + min;
		g = max;
		b = min;
	} else if (h<180) {
		r = min;
		g = max;
		b = ((h-120)/60) * (max-min) + min;
	} else if (h<240) {
		r = min;
		g = ((240-h)/60) * (max-min) + min;
		b = max;
	} else if (h<300) {
		r = ((h-240)/60) * (max-min) + min;
		g = min;
		b = max;
	} else {
		r = max;
		g = min;
		b = ((360-h)/60) * (max-min) + min;
	}
	// safety
	r = Math.round(r);
	g = Math.round(g);
	b = Math.round(b);
	if (r<0) r=0;
	if (g<0) g=0;
	if (b<0) b=0;
	if (255<r) r=255;
	if (255<g) g=255;
	if (255<b) b=255;

	// 文字列変換
	r = (r<16 ? '0' : '') + r.toString(16);
	g = (g<16 ? '0' : '') + g.toString(16);
	b = (b<16 ? '0' : '') + b.toString(16);
	return '#' + r + g + b;
}

//////////////////////////////////////////////////////////////////////////////
// ●色名の翻訳
//////////////////////////////////////////////////////////////////////////////
	var n2msg = {};
{
	// 色名の翻訳テキスト
	var ary =$('#attr-msg').html().split("\n");
	for(var i=0; i<ary.length; i++) {
		var line = ary[i];
		var ma = line.match(/(.*?)\s*=\s*([^\s]*)/);
		if (ma) n2msg[ma[1]] = ma[2];
	}
}
function name2msg(name) {
	for(var n in n2msg)
		name = name.replace(n, n2msg[n]);
	return name;
}

//////////////////////////////////////////////////////////////////////////////
// ●逆ポーランドに変換
//////////////////////////////////////////////////////////////////////////////
// 演算子優先度
var oph = {
	'(': 1,
	')': 1,
	'+': 10,
	'-': 10,
	'*': 20,
	'/': 20
};

function exp_to_poland(exp) {
	exp = exp.replace(/^\s*(.*?)\s*$/, "$1");
	exp = exp.replace(/\s*([\+\-\(\)\*])\s*/g, "$1");
	exp = exp.replace(/^\-/,  '0-');
	exp = exp.replace(/\(-/g,'(0-');
	exp = exp.replace(/\s+/g, ' ');
	exp = '(' + exp + ')';

	var ary = [];
	while(exp.length) {
		var re = exp.match(/^(.*?)([ \+\-\(\)\*\/])(.*)/);
		if (!re) return;		// error
		if (re[2] == ' ') return;	// error
		if (re[1] != '') {
			var x = re[1].replace(/^\#([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])$/, "#$1$1$2$2$3$3");
			if (!( x.match(/^\#[0-9a-fA-F]{6}$/)
			    || x.match(/^\d+(?:\.\d+)?$/)
			    || x.match(/^[A-Za-z]\w*$/)
			   ) ) return ;			// error;
			ary.push(x);
		}
		ary.push(re[2]);
		exp = re[3];
	}

	// 変換処理
	var st = [];
	var out= [];
	for(var i=0; i<ary.length; i++) {
		var x = ary[i];
		if (! x.match(/[\+\-\(\)\*\/]/)) {
			out.push(x);
			continue;
		}
		// 演算子
		var xp = oph[x];	// そのまま積む
		if (x == '(' || st.length == 0 || oph[ st[st.length-1] ]<xp) {
			if (x == ')') return;	// error
			st.push(x);
			continue;
		}
		// 優先度の低い演算子が出るまでスタックから取り出す
		while(st.length) {
			var y  = st.pop();
			var yp = oph[y];
			if (yp < xp)  break;
			if (y == '(') break;
			out.push(y);
		}
		if (x != ')') st.push(x);
	}
	if (st.length) return;	// error
	return out;
}

//////////////////////////////////////////////////////////////////////////////
// ●逆ポーランド式を実行
//////////////////////////////////////////////////////////////////////////////
function exec_poland(p) {
	var st = [];
	// console.log(p.join(' '));
	
	for(var i=0; i<p.length; i++) {
		var op = p[i];
		if (!oph[op]) {
			var x = op;
			if (x.substr(0,1) == '#')
				x = parse_rgb(x);
			else if (x.match(/^[A-Za-z]\w*$/)) {
				var obj = $('#inp-'+x);
				x = parse_rgb( obj.data('val') || obj.val() );
			} 
			if (x == '') return;	// error
			st.push(x);
			continue;
		}
		// 演算子
		var y = st.pop();
		var x = st.pop();
		var xary = x instanceof Array;
		var yary = y instanceof Array;
		if (x == '' || y == '') return;	// error

		if (op == '+' || op == '-') {
			var func = (op=='+')
				 ? function(a,b) { return a+b; }
				 : function(a,b) { return a-b; }
			if (!xary && !yary)
				x = func(x,y);
			else if (xary && yary)
				for(var i=0; i<3; i++)
					x[i] = func(x[i], y[i]);
			else return;	// error
		}

		if (op == '*' || op == '/') {
			var func = (op=='*')
				 ? function(a,b) { return a*b; }
				 : function(a,b) { return a/b; }
			if (!xary && !yary)
				x = func(x,y);
			else if (xary && !yary)
				for(var i=0; i<3; i++)
					x[i] = func(x[i], y);
			else if (!xary && yary)
				for(var i=0; i<3; i++)
					x[i] = func(x, y[i]);
			else return;	// error
		}

		st.push(x);
	}
	if (st.length != 1 || !st[0] instanceof Array) return;	// error
	return rgb2hex( st[0] );
}

function parse_rgb(rgb) {
	var ma = rgb.match(/#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})/);
	if (!ma) return ;
	return [parseInt('0x' + ma[1]), parseInt('0x' + ma[2]), parseInt('0x' + ma[3])];
}

function rgb2hex(ary) {
	for(var i=0; i<3; i++) {
		ary[i] = Math.round(ary[i]);
		if (ary[i]<   0) ary[i]=0;
		if (ary[i]>0xff) ary[i]=0xff;
	}
	// 文字列変換
	var r = (ary[0]<16 ? '0' : '') + ary[0].toString(16);
	var g = (ary[1]<16 ? '0' : '') + ary[1].toString(16);
	var b = (ary[2]<16 ? '0' : '') + ary[2].toString(16);
	return '#' + r + g + b;
}

//############################################################################
});