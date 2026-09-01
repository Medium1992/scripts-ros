# scripts-ros :: lists/FWD_update_RU_list.rsc
# YOUR list. Russian services that must NOT go through the proxy -- they are
# forwarded to a domestic resolver instead, so geo-restricted local sites keep
# working and the proxy carries less traffic.

:global AddressList ""
:global ForwardTo "Yandex"

:global rosSets {
    {"base"="https://raw.githubusercontent.com/Medium1992/MikroTik_DNS_FWD/refs/heads/main/for_scripts";
     "items"={
        "category-gov-ru";"category-bank-ru";"category-retail-ru";
        "category-travel-ru";"category-ecommerce-ru";"category-entertainment-ru";
        "mailru-group";"vk";"ok";"yandex";"ozon";"wildberries";"x5";"okko";
        "kinopoisk"
     }}
}
