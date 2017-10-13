
# gitbook initial
gitbook build
mv _book ../
cd ../_book

# git push --force
git init
git checkout --orphan gh-pages
git add .
git commit -am 'release new version' -s
git remote add origin git@github.com:Desgard/iOS-Source-Probe.git
git push origin gh-pages  --force

# return 
cd ../iOS-Source-Probe/

