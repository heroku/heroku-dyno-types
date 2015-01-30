## installation

`heroku plugins:install https://github.com/heroku/heroku-dyno-types.git`

## enable new dyno types to an app

`heroku labs:enable new-dyno-sizes --app yourapp`

## see current dyno type

`heroku ps:type --app yourapp`

## change dyno type

```
heroku ps:type free       --app yourapp
heroku ps:type hobby      --app yourapp
heroku ps:type basic      --app yourapp
heroku ps:type production --app yourapp
```


