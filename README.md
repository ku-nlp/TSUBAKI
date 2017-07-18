# 検索エンジン基盤 TSUBAKI

TSUBAKIは、科研特定領域研究「情報爆発」(2006年度〜2010年度)において、京
都大学黒橋・河原研究室が中心となって開発した検索エンジン基盤です。その
特徴は、構文・格解析、同義語・句のマッチングなど深い言語解析技術に基づ
く検索です。1CPUあたり100万文書程度の検索が可能で、複数CPUの並列化によ
り大規模文書集合の検索に対応しています。現在、日本語文書と英語文書の検
索が可能です。

以下の説明では、1CPU(localhostのみ)で検索を行うことを想定しています。並
列化による100万件以上の文書の検索については、本README最後の注意事項をご
覧ください。


## 準備

### 必要なライブラリ、モジュールのインストール

- 必要なライブラリのインストール
    - [libxml](http://xmlsoft.org/)
    - [BerkeleyDB](http://www.oracle.com/technetwork/products/berkeleydb/)
- 必要なPerlモジュールのインストール (CPAN等を用いてインストール)
    - Unicode::Japanese
    - PerlIO::gzip
    - IO::Uncompress::Gunzip
    - Archive::Zip
    - XML::LibXML
    - XML::Writer
    - CDB_File
    - BerkeleyDB
    - MLDBM
    - Text::Darts
    - Error (Module::Metadata, version, Perl::OSType, Module::Buildも必要)

本パッケージのcpanディレクトリに、上記のPerlモジュールのtarballを同梱していますので、必要に応じてご利用ください。

### 言語解析ツール・データベースのインストール

- 以下の依存ツールをこのディレクトリに設置する必要があります
    - www2sf
    - Utils
    - SynGraph
- 日本語の文書を検索する場合に必要なツール・データベースのインストール
    - 日本語形態素解析システム[JUMAN](http://nlp.ist.i.kyoto-u.ac.jp/index.php?JUMAN)のインストール
        - Perlモジュールもインストールしてください
    - 日本語構文・格解析システム[KNP](http://nlp.ist.i.kyoto-u.ac.jp/index.php?KNP)のインストール
        - Perlモジュールもインストールしてください
    - SynGraph日本語データベース(同義語・句の辞書)のダウンロード
        - [データ](http://nlp.ist.i.kyoto-u.ac.jp/nl-resource/SynGraph/SynGraph-wikipedia-syndb.tar.bz2)をダウンロードし、TSUBAKI直下(このディレクトリ)にて展開してください。
        - データベースがSynGraph/syndb以下に展開されます。
    - 複合名詞の文書頻度データベースのダウンロード
        - [データ](http://nlp.ist.i.kyoto-u.ac.jp/nl-resource/TSUBAKI/data/cns.100M.cls.df1000.cdb)をダウンロードし、TSUBAKI直下のdataディレクトリに設置してください。
- 英語の文書を検索する場合に必要なツールのインストール
    - [Stanford Parser](http://nlp.stanford.edu/software/lex-parser.shtml)のインストール
    - 英語の同義語・句のデータを別途用意すれば、SynGraphデータベース形式に変換して使うことができます。詳細は、SynGraphのドキュメントをご覧ください。


### TSUBAKI設定ファイルの生成

以下では、このREADMEがあるディレクトリを``$TSUBAKI_DIR``と表します。

``$TSUBAKI_DIR``において以下のように``./setup.sh``を実行することにより、インデックスデータの場所や解析ツールのインストール場所などを含むTSUBAKIの設定ファイルを自動生成します。

- 例1: 日本語サンプル文書データを対象にする場合
```
./setup.sh -s sample_doc/ja/src_doc -d /somewhere/data -L
```
(/somewhere/data以下にインデックスなどのデータを出力します)

- 例2: 英語サンプル文書データを対象にする場合
```
./setup.sh -e -s sample_doc/en/src_doc -d /somewhere/data -L -f /somewhere/stanford-parser-full-2013-06-20
```
- 例3: あるディレクトリ``(/somewhere/src_doc_html)``以下にあるHTML文書データ(gzip済み)を対象にする場合
```
./setup.sh -s /somewhere/src_doc -d /somewhere/data -z
```
(``/somewhere/src_doc``以下の``"*.html.gz"``ファイルを再帰的に探索します)

#### ./setup.shの重要なオプションの説明
```
-s 検索対象文書パス       : 検索対象文書の場所を指定
-d 出力データパス         : インデックスなどのデータ出力場所を指定
-j                        : 日本語の文書を検索する場合 (default)
-e                        : 英語の文書を検索する場合
-f Parserのパス           : 英語の文書を検索する場合に、Stanford Parserの場所を指定
-c 出力設定ファイル名	  : 出力する設定ファイル名を指定 (default: $TSUBAKI_DIR/conf/configure)
-z                        : 検索対象文書がgzip圧縮されている場合に指定
-L                        : 検索対象文書をシンボリックリンクではなくコピーする場合に指定
-u                        : HTMLがUTF-8化されている場合に指定
-Z                        : 検索対象文書がzipで固められている場合に指定
-a                        : 検索対象文書を追加する場合に指定
```

以下では、上記の例1を実行し、日本語サンプル文書データを対象にしていると
して説明します。日本語サンプル文書データ以外を用いる場合に設定が必要な
箇所にはその旨を記述しています。


### 検索サーバプログラムのコンパイル

``$TSUBAKI_DIR``において、``make``を実行してください。
コンパイルできない場合は，コンパイルの指定を試してみて下さい。
```
make CC=gcc CXX=g++
```


## ID付与

すべてのhtml文書は、「(10桁のID).html」の形式で扱います。以下を実行す
ることにより、``sample_doc/ja/src_doc``以下のhtml文書に対して、10桁のIDを
付与し、``$DATADIR/html``以下に配置します。

```
make html
```


setup.shで-Zオプションを利用した場合はテンポラリディレクトリが大きい必要があるので、/tmpよりも大きいディレクトリをTMP_DIR_BASEオプションで指定してください。
```
make TMP_DIR_BASE=/somewhere/tmp html
```

## TSUBAKI標準フォーマット変換, インデックス生成

検索対象文書に言語解析を適用し、その解析結果をXML形式で出力します。(以
後、このXML形式を「TSUBAKI標準フォーマット」と呼びます。) そして、
TSUBAKI標準フォーマットデータからインデックスを生成します。
$TSUBAKI_DIR において次のように実行してください。

```
make indexing
```

 テンポラリディレクトリとしてデフォルトでは/tmpを使いますが、/tmpに
十分な容量がない場合は、次のようにテンポラリディレクトリを指定して
ください。100万文書あたり100GB程度必要です。

```
make TMP_DIR_BASE=/somewhere/tmp indexing
```

indexingを一度にすべてではなく、例えば、1,000万ページずつ行いたい場合、
``sf2index/Makefile``の``$(HTML_FIRST_DIR)``を修正する。
以下の例では0000,0001, ..., 0009以下だけをindexingの対象とする(=合計1,000万ページ)。
```
(修正前)
HTML_FIRST_DIR := $(HTML_TOP_DIR)/????
(修正後)
HTML_FIRST_DIR := $(HTML_TOP_DIR)/000?
```
 
## 検索

### 検索テスト

$TSUBAKI_DIRにおいて、"./search.sh -c conf/configure クエリ"
を実行して検索のテストをします。クエリはUTF-8で入力してください。

```
./search.sh -c conf/configure 京大	# hitcountが6になる
./search.sh -c conf/configure 紅葉	# hitcountが5になる
```

`./search.sh -c conf/configure 京大`の場合、以下のような出力が得られます。



```
--- QUERY (sexp) ---
( (ROOT (OR_MAX ((京大/きょうだい 1 3 1 0 0)) ((京大/きょうだい<反義語> 1 3 0 0 0)) ((s31570:京都大学 1 3 0 0 0)) ((s31570:京都大学<反義語> 1 3 0 0 0)) ) (OR_MAX ((京大/きょうだい 3 3 1 2 0)) ((京大/きょうだい<反義語\
> 3 3 0 2 0)) ((s31570:京都大学 3 3 0 2 0)) ((s31570:京都大学<反義語> 3 3 0 2 0)) ) ) )
--- RESULT ---
11      110.38  176     0       1       1       6       6       [京大/きょうだい 22.6443 1 3,s31570:京都大学 16.8055 0.495 3,OR_MAX 22.6443 1 3,] [京大/きょうだい,6#s31570:京都大学,6#OR_MAX,6#]
8       109.784 245     0       1       1       65      65      [京大/きょうだい 21.9826 1 3,s31570:京都大学 16.0798 0.495 3,OR_MAX 21.9826 1 3,] [京大/きょうだい,65#s31570:京都大学,65#OR_MAX,65#]
28      109.406 291     0       1       1       222     222     [京大/きょうだい 21.5626 1 3,s31570:京都大学 15.6299 0.495 3,OR_MAX 21.5626 1 3,] [京大/きょうだい,222#s31570:京都大学,222#OR_MAX,222#]
35      104.536 238     0       1       1       111     111     [s31570:京都大学 16.1506 0.495 3,OR_MAX 16.1506 0.495 3,] [s31570:京都大学,111#OR_MAX,111#]
41      103.708 334     0       1       1       287     287     [s31570:京都大学 15.2315 0.495 3,OR_MAX 15.2315 0.495 3,] [s31570:京都大学,287#OR_MAX,287#]
32      99.6438 1045    0       1       1       481     481     [s31570:京都大学 10.7153 0.495 3,OR_MAX 10.7153 0.495 3,] [s31570:京都大学,481#OR_MAX,481#]

hitcount 6
HOSTNAME basil200 39999
SEARCH_TIME 1.80221
SCORE_TIME 0.0479221 0.000953674
SORT_TIME 0.000953674
TOTAL_TIME 1.86992
```

「QUERY (sexp)」はQueryの内部表現を表しており、一番内側の括弧内の意味は順に以下のとおりです。
- term
- termtype(必須:1, オプショナル:3)
- DF
- nodeタイプ(termが単語の場合1, SYNノードの場合0)
- indexタイプ(termが単語の場合0, 係り受けの場合1, 単語の場合(アンカー用)2, 係り受けの場合(アンカー用)3)
- FeatureBit(その他の素性)

「RESULT」以下はヒットした文書を表わしており、一行が1文書で、順に`文書ID スコア 文書長 ページランク strict_term_feature proximate_feature best_begin best_end [マッチしたterm集合(スコアあり)] [マッチしたterm集合(pos list)]
マッチしたterm集合(スコアあり): 「,」がterm区切り (term スコア 頻度 DF)
マッチしたterm集合(pos list): 「#」がterm区切り, 「term, (pos集合)」`を表しています。

SCORE_TIMEの1番目は検索必須のtermに対するスコア計算、2番目はオプショナルのtermに対するスコア計算にかかった時間を表しています。


### ブラウザからの検索

ブラウザから検索するためには、localhostでsshdとhttpdが起動している必要
があります。次のようにして、sshdとhttpdが起動していることを確認してくだ
さい。

```
ps aux | grep sshd
ps aux | grep httpd
```

これらが起動していない場合は、システム設定を変更して起動してください。

TSUBAKIでは、検索サーバとスニペットサーバを利用します(構成図: 
doc/tsubaki-configuration.pdf)。検索サーバとスニペットサーバを次のよう
にして起動します。このスクリプトの実行によって、localhostにsshし、これ
らのサーバを起動しています。

```
scripts/server-all.sh -c conf/configure start
```

サーバを止めるには、上記のstartをstopとして実行してください。

検索フロントエンド``($TSUBAKI_DIR/cgi/index.cgi)``にWebブラウザでアクセスし、
クエリを入力して検索を実行します。

  例) ``http://localhost/``が``/var/www/html``ディレクトリに対応している場合
      は、``ln -s `pwd` /var/www/html``を実行することによって、
      /var/www/html直下にTSUBAKIディレクトリへのシンボリックリンクをは
      ります。Webブラウザでhttp://localhost/TSUBAKI/cgi/index.cgi にア
      クセスします。

ブラウザでindex.cgiのソースコードが表示される場合は、httpdの設定で
CGIが実行可能となっていることを確認してください (Apacheでは
``Options ExecCGI``と``AddHandler cgi-script .cgi``)。

### APIによる検索

``samplecode/`` 以下にC, Java, Perl, Pythonによるサンプルコードがありますので、そちらを参照して下さい。

## 注意事項

- 検索対象文書の形式としては、現在のところHTMLのみに対応しています。
- 大規模文書セットに対するTSUBAKI標準フォーマット変換およびインデックス
  生成を行う場合に、これらに要する時間を短縮するために並列化することを
  お勧めします。このためには、"make"に"-j 並列数"オプションを付けて実行
  します。さらに、クラスタ環境で並列に実行するには、gxp makeを利用する
  ことができます。詳細は、http://www.logos.ic.i.u-tokyo.ac.jp/gxp/ を参
  照してください。
- 100万件以上の文書を検索するには、複数の検索サーバとスニペットサーバを
  起動する必要があります。このためには、設定ファイル(conf/configure)に
  おいて、次のようにSEARCH_SERVERSとSNIPPET_SERVERSの行をサーバ台数分コ
  ピーし、サーバ名を記入してください。
```
SEARCH_SERVERS	server01	39999	/somewhere/data/idx/0000	none
SEARCH_SERVERS	server02	39999	/somewhere/data/idx/0001	none
SNIPPET_SERVERS	server01	59001	0000
SNIPPET_SERVERS	server02	59001	0001
```
- ``scripts/copy-idx-localdisk.sh``を使ってidxファイルをローカルディス
  クに配置して下さい。使い方は``scripts/copy-idx-localdisk.sh``を参照して
  下さい。
- 複数の文書セットに対して検索するためには、「TSUBAKI設定ファイルの生成」
  において、``./setup.sh``に"-c 出力設定ファイル名"を付けて実行し、異なる名
  前の設定ファイルを生成してください。また、``cgi/tsubaki-cgi.conf``にその
  設定ファイル名を記入してください。


## ドキュメント

より詳細なドキュメントは、[TSUBAKI Wiki](http://orchid.kuee.kyoto-u.ac.jp/tsubaki-wiki/)を参照してください。