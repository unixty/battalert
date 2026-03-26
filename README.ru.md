# BattAlert

BattAlert — лёгкий скрипт мониторинга батареи для Linux-ноутбуков.

Он работает как `systemd` сервис и отправляет десктоп-уведомления (со звуком), когда заряд батареи достигает заданных порогов.

## Возможности

- Уведомления на верхний и нижний порог заряда
- Повтор критических уведомлений, пока не изменится статус зарядки
- Воспроизведение звука для верхнего/нижнего порога
- Поддержка языков уведомлений: английский и русский
- Интерактивный установщик с выбором порогов и языка

## Параметры по умолчанию

- Нижний порог: `40%`
- Верхний порог: `80%`
- Язык: `en`

## Установка

Запускать из директории проекта:

```bash
sudo bash install.sh
```

Установщик спросит:

- Нижний порог в процентах
- Верхний порог в процентах
- Язык (`en` или `ru`)

После этого он:

- Установит `battalert.sh` в `/usr/local/bin/battalert.sh`
- Установит `battalert.service` в `/etc/systemd/system/battalert.service`
- Создаст `/etc/default/battalert` с выбранными настройками
- Включит и запустит `battalert.service`

## Удаление

Запускать из директории проекта:

```bash
sudo bash uninstall.sh
```

Скрипт удаления:

- Остановит и отключит `battalert.service`
- Удалит `/usr/local/bin/battalert.sh`
- Удалит `/etc/systemd/system/battalert.service`
- Перезагрузит конфигурацию `systemd`
- Спросит, удалять ли `/etc/default/battalert`

## Конфигурация

Файл настроек:

`/etc/default/battalert`

Пример:

```bash
LOWER=40
UPPER=80
LANG_CODE="en"
```

Если меняете конфиг вручную, перезапустите сервис:

```bash
sudo systemctl restart battalert.service
```

## Логи

Файл логов:

`/tmp/battalert.log`

## Команды сервиса

```bash
sudo systemctl status battalert.service
sudo systemctl restart battalert.service
sudo systemctl stop battalert.service
sudo systemctl disable battalert.service
```
