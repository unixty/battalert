# BattAlert

BattAlert — лёгкий скрипт мониторинга батареи для Linux-ноутбуков.

Он работает как `systemd` сервис и отправляет десктоп-уведомления (со звуком), когда заряд батареи достигает заданных порогов.

## Возможности

- Уведомления на верхний и нижний порог заряда
- Повтор критических уведомлений, пока не изменится статус зарядки
- Воспроизведение звука для верхнего/нижнего порога
- Поддержка языков уведомлений: английский и русский
- Настраиваемый целевой уровень громкости сигнала (`VOLUME`, по умолчанию `80`)
- Опциональная блокировка сна при зарядке (`INHIBIT_SLEEP_ON_AC`)
- Опциональное временное повышение системной громкости во время сигнала (`BOOST_SYSTEM_VOLUME_ON_ALERT`)
- Интерактивный установщик с выбором порогов, языка и параметров звука/сна

## Параметры по умолчанию

- Нижний порог: `40%`
- Верхний порог: `80%`
- Язык: `en`
- Целевой уровень громкости сигнала: `80`
- Блокировка сна на зарядке: `1`
- Временное повышение системной громкости на сигнал: `0`

## Зависимости

Обязательные команды:

- `systemd` (`systemctl`, `systemd-inhibit`)
- `notify-send`
- `gdbus`
- `sudo`
- `pw-cat` (обычно из пакета `pipewire-audio-client-libraries`, `pipewire-bin` или `pipewire`)

Опционально, но рекомендуется:

- `acpi`
- `wpctl`, если `BOOST_SYSTEM_VOLUME_ON_ALERT=1`

## Установка

Запускать из директории проекта:

```bash
sudo bash install.sh
```

Установщик спросит:

- Нижний порог в процентах
- Верхний порог в процентах
- Язык (`en` или `ru`)
- Блокировать сон при зарядке (`1` или `0`)
- Временно повышать системную громкость для сигнала (`1` или `0`)
- Целевой уровень громкости сигнала (`0-100`), если включено временное повышение системной громкости

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
VOLUME=70
INHIBIT_SLEEP_ON_AC=1
BOOST_SYSTEM_VOLUME_ON_ALERT=0
```

Если `BOOST_SYSTEM_VOLUME_ON_ALERT=1`, значение `VOLUME` используется как временный целевой уровень системной громкости для сигнала, но только если текущий sink находится в `mute` или ниже этого уровня.

Если `BOOST_SYSTEM_VOLUME_ON_ALERT=0`, скрипт проигрывает сигнал через `pw-cat --volume=1` и не меняет системную громкость.

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
