**NOTE:** This plugin has been archived and is no longer maintained. It is not installable with the current node-based CLI.

## installation

`heroku plugins:install https://github.com/heroku/heroku-dyno-types.git`

## enable new dyno types to an app

`heroku labs:enable new-dyno-sizes --app yourapp`

## see current dyno type

`heroku dyno:type --app yourapp`

## change dyno type

```
heroku dyno:type free        --app yourapp
heroku dyno:type hobby       --app yourapp
heroku dyno:type standard-1x --app yourapp
heroku dyno:type standard-2x --app yourapp
heroku dyno:type performance --app yourapp
```


