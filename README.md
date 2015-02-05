## installation

`heroku plugins:install https://github.com/heroku/heroku-dyno-types.git`

## enable new dyno types to an app

`heroku labs:enable new-dyno-sizes --app yourapp`

## see current dyno type

`heroku dyno:type --app yourapp`

## change dyno type

```
heroku dyno:type free       --app yourapp
heroku dyno:type hobby      --app yourapp
heroku dyno:type basic      --app yourapp
heroku dyno:type production --app yourapp
```


