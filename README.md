# :sparkles: XRay Vless Reality + MikroTik L009 :sparkles:


![img](Demonstration/logo.png)

:dizzy: Аналог [AmneziaWG + MikroTik](https://github.com/catesin/AmneziaVPN-MikroTik)


В данном репозитории рассматривается работа MikroTik RouterOS V7.18.2+ с протоколом **XRay Vless Reality**. Здесь рассмтариваем варинт с контейнеров внутри.

Предполагается что вы уже настроили серверную часть Xray например [с помощью панели управления 3x-ui](https://github.com/MHSanaei/3x-ui) и протестировали конфигурацию клиента например на смартфоне или персональном ПК.

:school: Внимание! Инструкция среднего уровня сложности. Перед применением настроек вам необходимо иметь опыт в настройке MikroTik уровня сертификации MTCNA. 

Присутствуют готовый контейнер на [Docker Hub](https://hub.docker.com/u/bestnaf) который можно сразу использовать внутри RouterOS.

------------

* [Преднастройка RouterOS](#Pre_edit)
* [RouterOS с контейнером](#R_Xray_1)
	- [Сборка контейнера на Windows](#R_Xray_1_windows)
	- [Готовые контейнеры](#R_Xray_1_build_ready)
	- [Настройка контейнера в RouterOS](#R_Xray_1_settings)
	

------------

<a name='Pre_edit'></a>
## Преднастройка RouterOS

Создадим отдельную таблицу маршрутизации:
```
/routing table 
add disabled=no fib name=r_to_vpn
```
Добавим address-list "to_vpn" что бы находившиеся в нём IP адреса и подсети заворачивать в пока ещё не созданный туннель
```
/ip firewall address-list
add address 0.0.0.0/1 list=to_vpn
```
можно не добавлять все адреса сразу а добавить только 8.8.8.8 для проверки

Добавим address-list "RFC1918" что бы не потерять доступ до RouterOS при дальнейшей настройке
```
/ip firewall address-list
add address=10.0.0.0/8 list=RFC1918
add address=172.16.0.0/12 list=RFC1918
add address=192.168.0.0/16 list=RFC1918
```
ЕЩЕ НУЖНО БУДЕТ ПОТОМ ДОБАВИТЬ В ЭТОТ ЖЕ СПИСОК, IP АДРЕС ВАШЕГО VPN VLESS ДЛЯ ДОСТУПА ТУДА НАПРЯМУЮ


Добавим правила в mangle для address-list "RFC1918" и переместим его в самый верх правил
```
/ip firewall mangle
add action=accept chain=prerouting dst-address-list=RFC1918 in-interface-list=!WAN
```

Добавим правило транзитного трафика в mangle для address-list "to_vpn"
```
/ip firewall mangle
add action=mark-connection chain=prerouting connection-mark=no-mark dst-address-list=to_vpn in-interface-list=!WAN \
    new-connection-mark=to-vpn-conn passthrough=yes
```
Добавим правило для транзитного трафика отправляющее искать маршрут до узла назначения через таблицу маршрутизации "r_to_vpn", созданную на первом шаге
```
add action=mark-routing chain=prerouting connection-mark=to-vpn-conn in-interface-list=!WAN new-routing-mark=r_to_vpn \
    passthrough=yes
```
Маршрут по умолчанию в созданную таблицу маршрутизации "r_to_vpn" добавим чуть позже.

:exclamation:Два выше обозначенных правила будут работать только для трафика, проходящего через маршрутизатор. 
Если вы хотите заворачивать трафик, генерируемый самим роутером (например команда ping 8.8.8.8 c роутера для проверки туннеля в контейнере), тогда добавляем ещё два правила (не обязательно). 
Они должны находиться по порядку, следуя за вышеобозначенными правилами.
```
/ip firewall mangle
add action=mark-connection chain=output connection-mark=no-mark \
    dst-address-list=to_vpn new-connection-mark=to-vpn-conn-local \
    passthrough=yes
add action=mark-routing chain=output connection-mark=to-vpn-conn-local \
    new-routing-mark=r_to_vpn passthrough=yes
```

------------
<a name='R_Xray_1'></a>
<a name='R_Xray_1_windows'></a>
## RouterOS с контейнером

### Сборка контейнера

Данный пункт настройки подходит только для устройств с архитектурой ARM. Перед запуском контейнера в RouteOS убедитесь что у вас [включены контейнеры](https://help.mikrotik.com/docs/display/ROS/Container).  С полным списком устройств можно ознакомится [тут](https://mikrotik.com/products/matrix). [Включаем поддержку контейнеров в RouterOS](https://www.google.com/search?q=%D0%9A%D0%B0%D0%BA+%D0%B2%D0%BA%D0%BB%D1%8E%D1%87%D0%B8%D1%82%D1%8C+%D0%BA%D0%BE%D0%BD%D1%82%D0%B5%D0%B9%D0%BD%D0%B5%D1%80%D1%8B+%D0%B2+mikrotik&oq=%D0%BA%D0%B0%D0%BA+%D0%B2%D0%BA%D0%BB%D1%8E%D1%87%D0%B8%D1%82%D1%8C+%D0%BA%D0%BE%D0%BD%D1%82%D0%B5%D0%B9%D0%BD%D0%B5%D1%80%D1%8B+%D0%B2+mikrotik).
Так же предполагается что на устройстве (или если есть USB порт с флешкой) имеется +- 50 Мбайт свободного места для разворачивания контейнера внутри RouterOS и +- 150 Мбайт в оперативной памяти. Если места в storage не хватает, его можно временно расширить [за счёт оперативной памяти](https://www.youtube.com/watch?v=uZKTqRtXu4M). После перезагрузки RouterOS, всё что находится в RAM, стирается. 

<a name='R_Xray_1_build_ready'></a>
**Где взять контейнер?** Его можно собрать самому из текущего репозитория каталога **"Containers"** или скачать готовый образ из [Docker Hub](https://hub.docker.com/u/bestnaf).
Скачав готовый образ [переходим сразу к настройке](#R_Xray_1_settings).


Для самостоятельной сборки следует установить подсистему Docker [buildx](https://github.com/docker/buildx?tab=readme-ov-file), "make" и "go".

1) Скачиваем [Docker Desktop](https://docs.docker.com/desktop/) и устанавливаем
2) Скачиваем каталог **"Containers"**
3) Открываем консоль и переходим в каталог **"Containers"** (cd <путь до каталога>)
4) Запускаем Docker с ярлыка на рабочем столе (окно приложения должно просто висеть в фоне при сборке) и через cmd собираем контейнер под выбранную архитектуру RouterOS

- ARMv8 (arm64/v8) — спецификация 8-го поколения оборудования ARM, которое поддерживает архитектуры AArch32 и AArch64.
- ARMv7 (arm/v7) — спецификация 7-го поколения оборудования ARM, которое поддерживает только архитектуру AArch32. 
- AMD64 (amd64) — это 64-битный процессор, который добавляет возможности 64-битных вычислений к архитектуре x86

Для ARMv8 (Containers\Dockerfile_arm64)
```
docker image prune -f

docker buildx build -f Dockerfile_arm64 --no-cache --progress=plain --platform linux/arm64/v8 --output=type=docker --tag user/docker-xray-vless:latest .
```

Для ARMv7 (Containers\Dockerfile_arm)
```
docker image prune -f

docker buildx build -f Dockerfile_arm --no-cache --progress=plain --platform linux/arm/v7 --output=type=docker --tag user/docker-xray-vless:latest .
```

Для amd64 (Containers\Dockerfile_amd64)
```
docker image prune -f

docker buildx build -f Dockerfile_amd64 --no-cache --progress=plain --platform linux/amd64 --output=type=docker --tag user/docker-xray-vless:latest .
```
Иногда процесс создания образа может подвиснуть из-за плохого соединения с интернетом. Следует повторно запустить сборку. 
После сборки образа вы можете загрузить контейнер в приватный репозиторий Docker HUB и продолжить настройку по [следующему пункту](#R_Xray_1_settings)


<a name='R_Xray_1_settings'></a>
### Настройка контейнера в RouterOS

В текущем примере на устройстве MikroTik флешки нет. Хранить будем всё с использованием расшаренного storage через оперативную память.
Если у вас есть USB порт и флешка, лучше размещать контейнер на ней.  
Можно комбинировать память загрузив контейнер в расшаренный диск [за счёт оперативной памяти](https://www.youtube.com/watch?v=uZKTqRtXu4M), а сам контейнер разворачивать в постоянной памяти.

Рекомендую создать пространство из ОЗУ хотя бы для tmp директории. Размер регулируйте самостоятельно:
```
/disk
add slot=ramstorage tmpfs-max-size=100M type=tmpfs
```

:exclamation:**Если контейнер не запускается на флешке.**
Например, вы хотите разместить контейнер в каталоге /usb1/docker/xray. Не создавайте заранее каталог xray на USB-флеш-накопителе. При создании контейнера добавьте в команду распаковки параметр "root-dir=usb1/docker/xray", в этом случае контейнер распакуется самостоятельно создав каталог /usb1/docker/xray и запустится без проблем.
```
/container/config/set tmpdir=usb1/tmp/
/container/config/set layer-dir=usb1/layer/
```

**В RouterOS выполняем:**

0) Подключем Docker HUB в наш RouterOS
```
/file add type=directory name=ramstorage
```
```
/container config
set ram-high=200.0MiB registry-url=https://registry-1.docker.io tmpdir=ramstorage
```
или
```
/container/config/set memory-high=300MiB tmpdir=usb1/tmp/ layer-dir=usb1/layer/ registry-url=https://registry-1.docker.io
```
1) Создадим интерфейс для контейнера
```
/interface veth add address=172.18.20.6/30 gateway=172.18.20.5 gateway6="" name=docker-xray-vless-veth
```

2) Добавим правило в mangle для изменения mss для трафика, уходящего в контейнер. Поместите его после правила с RFC1918 (его мы создали ранее).
```
/ip firewall mangle add action=change-mss chain=forward new-mss=1360 out-interface=docker-xray-vless-veth passthrough=yes protocol=tcp tcp-flags=syn tcp-mss=1420-65535
```

3) Назначим на созданный интерфейс IP адрес. IP 172.18.20.6 возьмёт себе контейнер, а 172.18.20.5 будет адрес RouterOS.
```
/ip address add interface=docker-xray-vless-veth address=172.18.20.5/30
```
4) В таблице маршрутизации "r_to_vpn" создадим маршрут по умолчанию ведущий на контейнер
```
/ip route add distance=1 dst-address=0.0.0.0/0 gateway=172.18.20.6 routing-table=r_to_vpn
```
5) Включаем masquerade для всего трафика, уходящего в контейнер.
```
/ip firewall nat add action=masquerade chain=srcnat out-interface=docker-xray-vless-veth
```
6) Создадим переменные окружения envs под названием "xvr", которые позже при запуске будем передавать в контейнер.
Параметры подключения Xray Vless вы должны взять из сервера панели 3x-ui. 

:anger: Пример импортируемой строки из 3x-ui раздела клиента "Details" (у вас настройки должны быть сгенерированы свои):
```
vless://e3203dfe-9s62-4de5-bf9b-ecd36c9af225@myhost.com:443?type=tcp&security=reality&pbk=fTndnleCTkK9_jtpwCAdxtEwJUkQ22oY1W8dTza2xHs&fp=chrome&sni=apple.com&sid=29d2d3d5a398&spx=%2wF#d
```
Размещаем данные параметры для передачи в контейнер
```
/container envs
add key=SERVER_ADDRESS name=xvr value=myhost.com
add key=SERVER_PORT name=xvr value=443
add key=USER_ID name=xvr value=e3203dfe-9s62-4de5-bf9b-ecd36c9af225
add key=ENCRYPTION name=xvr value=none
add key=FINGERPRINT_FP name=xvr value=chrome
add key=SERVER_NAME_SNI name=xvr value=apple.com
add key=PUBLIC_KEY_PBK name=xvr value=fTndnleCTkK9_jtpwCAdxtEwJUkQ22oY1W8dTza2xHs
add key=SHORT_ID_SID name=xvr value=29d2d3d5a398
add key=FLOW name=xvr value=xtls-rprx-vision
add key=SPIDER_X name=xvr value=/
```

7) Теперь создадим сам контейнер. Здесь вам нужно выбрать репозиторий из [Docker Hub](https://hub.docker.com/u/bestnaf) с архитектурой под ваше устройство.

- bestnaf/mikrotik-xray-vless-arm

Пример импорта контейнера в ramstorage (по факту в оперативную память) для arm64. Подставьте в ```remote-image``` нужный репозиторий и отредактируйте местоположение контейнера в ```root-dir``` при необходимости.

```
/container/add remote-image=catesin/xray-mikrotik-arm:latest \
  hostname=xray-vless interface=docker-xray-vless-veth \
  envlist=xvr start-on-boot=yes \
  root-dir=ramstorage/container-xray-mikrotik memory-high=200MiB
```
или 
```
/container/add remote-image=bestnaf/mikrotik-xray-vless-arm:latest \
  hostname=xray-vless interface=docker-xray-vless-veth \
  envlist=xvr start-on-boot=yes \
  root-dir=usb1/container-xray-mikrotik memory-high=300MiB
```
Подождите немного пока контейнер распакуется до конца. В итоге у вас должна получиться похожая картина, в которой есть распакованный контейнер и окружение envs. Если в процессе импорта возникают ошибки, внимательно читайте лог из RouterOS.

![img](Demonstration/1.1.png)

![img](Demonstration/1.2.png)

:anger:
Контейнер будет использовать только локальный DNS сервер на IP адресе 172.18.20.5. Необходимо разрешить DNS запросы TCP/UDP порт 53 на данный IP в правилах RouterOS в разделе ```/ip firewall filter```

Включить DNS-сервер на RouterOS:

/ip dns set servers=1.1.1.1,8.8.8.8 allow-remote-requests=yes

Убедиться, что firewall forward разрешает src=172.18.20.6 dst=172.18.20.5 proto=udp/tcp port=53.

8) Запускаем контейнер через WinBox в разделе меню Winbox "container". В логах MikroTik вы увидите характерные сообщения о запуске контейнера. 

:fire::fire::fire: Поздравляю! Настройка завершена.
 
По желанию логирование контейнера можно отключить что бы не засорялся лог RouteOS.


Чтобы разрешить fallback на обычный канал в случае недоступности контейнера нужно сделать
```
# BYPASS internal / mgmt subnets (stay local)
# add whatever LANs you have; these never use the VPN
/routing/rule/add action=lookup-only-in-table dst-address=192.168.0.0/16 table=main comment="Bypass: RFC1918 to main"

# BYPASS the container link and the Xray server itself
/routing/rule/add action=lookup-only-in-table dst-address=172.18.20.4/30 table=main comment="Bypass: veth /30"
/routing/rule/add action=lookup-only-in-table dst-address=38.244.170.102/32 table=main comment="Bypass: Xray server"

# SEND LAN -> try VPN first (use *lookup*, not lookup-only-in-table, to allow fallback)
/routing/rule/add action=lookup src-address=192.168.5.0/24 table=r_to_vpn comment="LAN -> try VPN"

# FALLBACK: if r_to_vpn has no usable default, use main
/routing/rule/add action=lookup src-address=192.168.5.0/24 table=main comment="LAN -> fallback to main"
```
```
# preferred (ROS v7)
/ip/firewall/nat/add chain=srcnat action=masquerade routing-table=r_to_vpn comment="NAT via Xray container"
# if your build doesn’t support routing-table match, use this instead:
# /ip/firewall/nat/add chain=srcnat action=masquerade out-interface=docker-xray-vless-veth comment="NAT via Xray container"
```
```
/ip/firewall/filter/disable 9
/ip/firewall/filter/disable 15
/ip/firewall/filter/add chain=forward action=fasttrack-connection hw-offload=yes \
  connection-state=established,related out-interface=!docker-xray-vless-veth \
  comment="FastTrack except VPN path"
```
```
# Remove prior MSS rule(s) targeting the veth and add this one:
/ip/firewall/mangle/remove [find where chain=forward action=change-mss out-interface=docker-xray-vless-veth]
/ip/firewall/mangle/add chain=forward protocol=tcp tcp-flags=syn out-interface=docker-xray-vless-veth \
  action=change-mss new-mss=clamp-to-pmtu comment="Clamp MSS for VPN path (veth)"
```

Можно добавить простой watchdog скрипт
```
/system/script/add name=vpn-watchdog policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon source="
:local rId [/ip/route find where routing-table=\"r_to_vpn\" dst-address=\"0.0.0.0/0\"];
/tool/fetch url=\"http://1.1.1.1\" routing-table=r_to_vpn output=none keep-result=no mode=http;
:if (\$status != \"finished\") do={
  /ip/route disable \$rId;
  :delay 30s;
  /ip/route enable \$rId;
}
"
/system/scheduler/add name=vpn-watchdog interval=1m on-event=vpn-watchdog
```
