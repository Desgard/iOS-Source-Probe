#!/bin/bash

gitbook install >/dev/null
echo 'Gitbook 插件更新成功'

gitbook build >/dev/null
echo '页面生成成功'

mv _book ../
cd ../_book

# git push --force
git init 
git checkout --orphan gh-pages >/dev/null
git add . >/dev/null
git commit -am 'release new version' -s >/dev/null
git remote add origin git@github.com:Desgard/iOS-Source-Probe.git
git push origin gh-pages  --force >/dev/null
echo 'Gitpages 发布成功'

# delete
cd ..
rm -rf _book/
echo '删除临时目录'

# return 
cd iOS-Source-Probe/

