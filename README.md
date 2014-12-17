## installation

`heroku plugins:install https://github.com/heroku/heroku-process-tiers.git`

## enable new tiers to an app

`heroku labs:enable new-dyno-sizes --app yourapp`

## see current process tier

`heroku ps:tier --app yourapp`

## change process tier

```
heroku ps:tier free       --app yourapp
heroku ps:tier hobby      --app yourapp
heroku ps:tier basic      --app yourapp
heroku ps:tier production --app yourapp
```


