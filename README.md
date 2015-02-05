## installation

`heroku plugins:install https://github.com/heroku/heroku-dyno-types.git`

## enable new dyno types to an app

`heroku labs:enable new-dyno-sizes --app yourapp`

## see current dyno type

`heroku dyno:resize --app yourapp`

## change dyno type

```
heroku dyno:resize free       --app yourapp
heroku dyno:resize hobby      --app yourapp
heroku dyno:resize basic      --app yourapp
heroku dyno:resize production --app yourapp
```


