<template>
  <a-row :gutter="16">
    <a-col :md="5" :sm="24">
      <a-card :bordered="false" :style="{background:'#fff'}">
        <div style="font-weight:600;padding:6px 12px 12px">插件套件 v3.6</div>
        <a-menu mode="inline" :selectedKeys="[active]" @click="onMenu">
          <a-menu-item v-for="m in menus" :key="m.key">
            <a-icon :type="m.icon"/>
            <span>{{m.title}}</span>
          </a-menu-item>
        </a-menu>
      </a-card>
    </a-col>
    <a-col :md="19" :sm="24">
      <a-card :bordered="false" :title="currentTitle">
        <component :is="currentComponent" :tab="currentTab" @refresh="noop"/>
      </a-card>
    </a-col>
  </a-row>
</template>

<script>
  import Prod from './Prod'
  import Ledger from './Ledger'
  import Check from './Check'
  import Audit from './Audit'
  import Stats from './Stats'
  import SalesProfit from './SalesProfit'
  import Finance from './Finance'
  import Barcode from './Barcode'
  import Invoice from './Invoice'
  import Pos from './Pos'
  import Print from './Print'
  import Master from './Master'
  import FixedAssetPage from './Asset'
  import Commission from './Commission'
  import FoodBatch from './FoodBatch'

  export default {
    name: 'PluginCenter',
    components: { Prod, Ledger, Check, Audit, Stats, SalesProfit, Finance, Barcode, Invoice, Pos, Print, Master, FixedAssetPage, Commission, FoodBatch },
    data() {
      return {
        active: 'prod',
        menus: [
          { key: 'prod', title: '生产管理', icon: 'build', comp: 'Prod' },
          { key: 'ledger', title: '总账管理', icon: 'account-book', comp: 'Ledger' },
          { key: 'check', title: '盘点管理', icon: 'audit', comp: 'Check' },
          { key: 'audit', title: '多级审核', icon: 'solution', comp: 'Audit' },
          { key: 'multi', title: '多属性库存', icon: 'appstore', comp: 'Stats', tab: 'multi' },
          { key: 'batch', title: '批次库存', icon: 'tags', comp: 'Stats', tab: 'batch' },
          { key: 'foodbatch', title: '批次与效期', icon: 'calendar', comp: 'FoodBatch' },
          { key: 'serial', title: '序列号统计', icon: 'barcode', comp: 'Stats', tab: 'serial' },
          { key: 'negative', title: '负库存统计', icon: 'warning', comp: 'Stats', tab: 'negative' },
          { key: 'profit', title: '利润报表', icon: 'line-chart', comp: 'Stats', tab: 'profit' },
          { key: 'sale', title: '销售分析', icon: 'bar-chart', comp: 'Stats', tab: 'sale' },
          { key: 'salesprofit', title: '销售利润', icon: 'fund', comp: 'SalesProfit' },
          { key: 'income', title: '收支项明细', icon: 'account-book', comp: 'Finance', tab: 'income' },
          { key: 'payment', title: '收付款明细', icon: 'pay-circle', comp: 'Finance', tab: 'payment' },
          { key: 'barcode', title: '条码打印', icon: 'barcode', comp: 'Barcode' },
          { key: 'invoice', title: '发票管理', icon: 'file-text', comp: 'Invoice' },
          { key: 'pos', title: '零售收银', icon: 'shopping-cart', comp: 'Pos' },
          { key: 'export', title: '单据导出', icon: 'export', comp: 'Stats', tab: 'export' },
          { key: 'print', title: '三联打印', icon: 'printer', comp: 'Print' },
          { key: 'vehicle', title: '车辆管理', icon: 'car', comp: 'Master', tab: 'vehicle' },
          { key: 'follow', title: '客户跟进', icon: 'message', comp: 'Master', tab: 'follow' },
          { key: 'asset', title: '固定资产', icon: 'bank', comp: 'FixedAssetPage' },
          { key: 'commission', title: '业绩提成', icon: 'red-envelope', comp: 'Commission' }
        ]
      }
    },
    computed: {
      current() {
        return this.menus.find(m => m.key === this.active) || this.menus[0]
      },
      currentComponent() {
        return this.current.comp
      },
      currentTab() {
        return this.current.tab || null
      },
      currentTitle() {
        return this.current.title
      }
    },
    methods: {
      onMenu(e) {
        this.active = e.key
      },
      noop() {}
    },
    watch: {
      '$route'(to) {
        const seg = (to.path || '').split('/').pop()
        if (seg && this.menus.some(m => m.key === seg)) {
          this.active = seg
        }
      }
    },
    created() {
      const seg = (this.$route.path || '').split('/').pop()
      if (seg && this.menus.some(m => m.key === seg)) {
        this.active = seg
      }
    }
  }
</script>
