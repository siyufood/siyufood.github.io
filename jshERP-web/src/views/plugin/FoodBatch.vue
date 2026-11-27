<template>
  <div>
    <a-radio-group v-model="view" button-style="solid" style="margin-bottom:12px">
      <a-radio-button value="ledger">批次台账</a-radio-button>
      <a-radio-button value="warning">效期预警</a-radio-button>
      <a-radio-button value="summary">批次汇总</a-radio-button>
    </a-radio-group>

    <!-- 台账 -->
    <crud-list v-if="view==='ledger'" ref="ledger" table="jsh_food_batch" :columns="columns" :fields="fields"
               :options="options" hint="填写生产日期与保质期天数后，到期日自动推算；状态支持 在库/已出库/已过期"/>

    <!-- 效期预警 -->
    <div v-else-if="view==='warning'">
      <a-row :gutter="12" style="margin-bottom:10px">
        <a-col :md="8" :sm="24">
          <a-card size="small" :bordered="false" style="background:#fff1f0">
            <a-statistic title="已过期" :value="counts.expired" suffix="个批次" valueStyle="color:#cf1322"/>
          </a-card>
        </a-col>
        <a-col :md="8" :sm="24">
          <a-card size="small" :bordered="false" style="background:#fffbe6">
            <a-statistic title="30 天内到期" :value="counts.within30" suffix="个批次" valueStyle="color:#d48806"/>
          </a-card>
        </a-col>
        <a-col :md="8" :sm="24">
          <a-card size="small" :bordered="false" style="background:#f6ffed">
            <a-statistic title="31-90 天到期" :value="counts.within90" suffix="个批次" valueStyle="color:#389e0d"/>
          </a-card>
        </a-col>
      </a-row>
      <a-form layout="inline" style="margin-bottom:10px">
        <a-form-item label="预警区间">
          <a-select v-model="range" style="width:150px">
            <a-select-option value="all">全部临期</a-select-option>
            <a-select-option value="expired">仅已过期</a-select-option>
            <a-select-option value="30">30 天内</a-select-option>
            <a-select-option value="90">90 天内</a-select-option>
          </a-select>
        </a-form-item>
        <a-form-item>
          <a-button type="primary" icon="reload" :loading="loading" @click="loadWarn">刷新</a-button>
        </a-form-item>
      </a-form>
      <a-table size="middle" bordered rowKey="id" :columns="warnColumns" :dataSource="warnRows"
               :pagination="{pageSize:10,showTotal:t=>`共 ${t} 条`}" :loading="loading" :scroll="{x:1100}"/>
    </div>

    <!-- 批次汇总 -->
    <div v-else>
      <a-table size="middle" bordered rowKey="materialName" :columns="summaryColumns" :dataSource="summaryRows"
               :pagination="{pageSize:10,showTotal:t=>`共 ${t} 条`}" :loading="loading" :scroll="{x:1000}"/>
    </div>
  </div>
</template>

<script>
  import CrudList from './components/CrudList'
  import { crud } from '@/api/plugin'

  function daysBetween(dateStr) {
    if (!dateStr) return null
    const d = new Date(String(dateStr).replace(/-/g, '/'))
    if (isNaN(d.getTime())) return null
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    return Math.round((d.getTime() - today.getTime()) / 86400000)
  }

  export default {
    name: 'PluginFoodBatch',
    components: { CrudList },
    data() {
      return {
        view: 'ledger',
        loading: false,
        range: 'all',
        rows: [],
        warnRows: [],
        summaryRows: [],
        options: {
          material: [],
          depot: [],
          batchStatus: [
            { value: '在库', label: '在库' },
            { value: '已出库', label: '已出库' },
            { value: '已过期', label: '已过期' }
          ]
        },
        columns: [
          { title: '批次号', dataIndex: 'batch_no', width: 150 },
          { title: '商品名称', dataIndex: 'material_name', width: 180 },
          { title: '仓库', dataIndex: 'depot_name', width: 120 },
          { title: '数量', dataIndex: 'qty', width: 100 },
          { title: '单位', dataIndex: 'unit', width: 80 },
          { title: '生产日期', dataIndex: 'production_date', width: 110 },
          { title: '保质期(天)', dataIndex: 'shelf_life_days', width: 100 },
          { title: '到期日期', dataIndex: 'expire_date', width: 110 },
          { title: '状态', dataIndex: 'status', width: 90 },
          { title: '操作', dataIndex: 'actions', scopedSlots: { customRender: 'actions' }, width: 140, fixed: 'right' }
        ],
        fields: [
          { key: 'batch_no', label: '批次号', placeholder: '如 20261127-A1' },
          { key: 'material_id', label: '商品', type: 'select', optionKey: 'material' },
          { key: 'material_name', label: '商品名称', placeholder: '选择商品后自动带出也可手填' },
          { key: 'depot_id', label: '仓库', type: 'select', optionKey: 'depot' },
          { key: 'depot_name', label: '仓库名称', placeholder: '选择仓库后自动带出' },
          { key: 'qty', label: '数量', type: 'number' },
          { key: 'unit', label: '单位', placeholder: '袋/箱/kg' },
          { key: 'production_date', label: '生产日期', type: 'date' },
          { key: 'shelf_life_days', label: '保质期(天)', type: 'number' },
          { key: 'expire_date', label: '到期日期', type: 'date' },
          { key: 'supplier', label: '来源/供应商' },
          { key: 'status', label: '状态', type: 'select', optionKey: 'batchStatus' },
          { key: 'remark', label: '备注', type: 'textarea' }
        ],
        warnColumns: [
          { title: '批次号', dataIndex: 'batch_no', width: 150 },
          { title: '商品名称', dataIndex: 'material_name', width: 180 },
          { title: '仓库', dataIndex: 'depot_name', width: 120 },
          { title: '数量', dataIndex: 'qty', width: 90 },
          { title: '到期日期', dataIndex: 'expire_date', width: 110 },
          { title: '剩余天数', dataIndex: 'remainDays', width: 100, customRender: (v) => (v === null ? '-' : (v < 0 ? `已过期 ${-v} 天` : `${v} 天`)) },
          { title: '预警级别', dataIndex: 'level', width: 110, customRender: (v) => {
              const color = v === '过期' ? 'red' : (v === '临期' ? 'orange' : 'green')
              return `<span style="color:${v === '过期' ? '#cf1322' : (v === '临期' ? '#d48806' : '#389e0d')}">${v}</span>`
            } },
          { title: '状态', dataIndex: 'status', width: 90 }
        ],
        summaryColumns: [
          { title: '商品名称', dataIndex: 'materialName' },
          { title: '批次数', dataIndex: 'batchCount', width: 100 },
          { title: '合计数量', dataIndex: 'totalQty', width: 120 },
          { title: '最近到期', dataIndex: 'nearestExpire', width: 120 },
          { title: '最早批次', dataIndex: 'earliestBatch', width: 160 },
          { title: '已过期批次', dataIndex: 'expiredCount', width: 110 }
        ]
      }
    },
    computed: {
      counts() {
        let expired = 0, within30 = 0, within90 = 0
        this.rows.forEach(r => {
          const d = daysBetween(r.expire_date)
          if (d === null) return
          if (d < 0) expired++
          else if (d <= 30) within30++
          else if (d <= 90) within90++
        })
        return { expired, within30, within90 }
      }
    },
    created() {
      crud.options({ type: 'material' }).then(r => { this.options.material = r.data || [] })
      crud.options({ type: 'depot' }).then(r => { this.options.depot = r.data || [] })
      this.loadWarn()
    },
    watch: {
      view(v) {
        if (v === 'warning' || v === 'summary') this.loadWarn()
      },
      range() { this.buildWarn() }
    },
    methods: {
      loadWarn() {
        this.loading = true
        crud.list({ table: 'jsh_food_batch', pageSize: 500 }).then(r => {
          this.rows = ((r.data || {}).rows) || []
          this.buildWarn()
          this.buildSummary()
        }).finally(() => { this.loading = false })
      },
      buildWarn() {
        let list = this.rows.map(r => {
          const d = daysBetween(r.expire_date)
          let level = '正常'
          if (d !== null) {
            if (d < 0) level = '过期'
            else if (d <= 30) level = '临期'
            else if (d <= 90) level = '关注'
          }
          return Object.assign({}, r, { remainDays: d, level })
        }).filter(r => r.remainDays !== null)
        if (this.range === 'expired') list = list.filter(r => r.remainDays < 0)
        else if (this.range === '30') list = list.filter(r => r.remainDays >= 0 && r.remainDays <= 30)
        else if (this.range === '90') list = list.filter(r => r.remainDays >= 0 && r.remainDays <= 90)
        else list = list.filter(r => r.remainDays <= 90)
        list.sort((a, b) => a.remainDays - b.remainDays)
        this.warnRows = list
      },
      buildSummary() {
        const map = {}
        this.rows.forEach(r => {
          const key = r.material_name || ('商品#' + (r.material_id || ''))
          if (!map[key]) {
            map[key] = { materialName: key, batchCount: 0, totalQty: 0, nearestExpire: '', earliestBatch: '', expiredCount: 0 }
          }
          const m = map[key]
          m.batchCount++
          m.totalQty += Number(r.qty || 0)
          if (r.expire_date) {
            if (!m.nearestExpire || r.expire_date < m.nearestExpire) m.nearestExpire = r.expire_date
          }
          if (r.batch_no && (!m.earliestBatch || r.batch_no < m.earliestBatch)) m.earliestBatch = r.batch_no
          const d = daysBetween(r.expire_date)
          if (d !== null && d < 0) m.expiredCount++
        })
        this.summaryRows = Object.keys(map).map(k => {
          const m = map[k]
          m.totalQty = Math.round(m.totalQty * 1000) / 1000
          return m
        }).sort((a, b) => b.expiredCount - a.expiredCount || a.materialName.localeCompare(b.materialName))
      }
    }
  }
</script>
