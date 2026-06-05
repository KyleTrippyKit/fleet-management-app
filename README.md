# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

Ruby version: 3.3.10

* System dependencies

```sh
sudo apt-get update
sudo apt-get install -y libvips42 libvips-dev
```

# For Fedora/RHEL
```sh
sudo dnf install -y libvips libvips-devel
```

# For macOS
```sh
brew install vips
```

* Configuration

The application supports .env files in the development and test environments

An example env file would include:

```env
DATABASE_HOST=<hostname>
DATABASE_NAME=fleet-management-dev
DATABASE_USERNAME=fleet-management-dev
DATABASE_PASSWORD=password
```

* Database creation

You will have to create a user for the development and test environments before running the db:create rails task.


```sh
./bin/rails db:create
./bin/rails db:cmigrate
```

* Database initialization

```sh
./bin/rails db:seed
```

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
