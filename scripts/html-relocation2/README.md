
# html-relocation2 (experimental)
- 従来のhtml-relocationは並列処理していなかった
- そのため，sourceに大量のファイルがあるとき，非常に処理に時間がかかった
- IDが連番にならない問題があった
- 空のファイルを作る問題もあった

- 以上の問題を解消したスクリプトで``make html``相当のことができる(実験的)


## 処理手順

- ファイルの一覧を取得
```
find -L source -type f | LANG=C sort |gzip > files.gz
```

- 各ファイルの所蔵件数を取得
- 各zipファイルの先頭ファイルIDを確定する
```
zcat files.gz | xargs python ./get-filenum.py  | python ./get-sum.py > ids
```
- 並列で新しいzipを作る
    - 例:
```
gxpc cd `pwd`
seq 0 10 10862 | xargs -i echo python ./make-newzip.py -i ids -o /path/to/out/html -t {} -n 10 | gxpc js -a cpu_factor=0.15 -a work_fd=0 -a log_file= -a state_dir=
```

- touchする
```
touch /path/to/out/html.relocation.done
```




