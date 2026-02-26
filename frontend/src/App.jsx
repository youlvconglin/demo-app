import { useState } from 'react'
import { Upload, Button, message, Card, Progress, Space, Typography, Row, Col } from 'antd'
import {
  InboxOutlined,
  FileTextOutlined,
  FileExcelOutlined,
  FilePptOutlined,
  MergeCellsOutlined,
  ScissorOutlined,
  ArrowLeftOutlined
} from '@ant-design/icons'
import axios from 'axios'
import './App.css'

const { Dragger } = Upload
const { Title, Text } = Typography

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || '/api/v1'

// 功能列表配置
const FEATURES = [
  {
    id: 'pdf2word',
    title: 'PDF 转 Word',
    description: '将 PDF 文档转换为可编辑的 Word 文件',
    seoDescription: '免费在线 PDF 转 Word 工具，支持将 PDF 文件快速转换为可编辑的 Word 文档（.docx格式）。保留原有格式、图片和布局，无需安装软件。',
    icon: <FileTextOutlined style={{ fontSize: 48, color: '#1890ff' }} />,
    accept: '.pdf',
    buttonText: '开始转换',
    keywords: 'PDF转Word, PDF转Word在线免费, PDF转换Word'
  },
  {
    id: 'pdf2excel',
    title: 'PDF 转 Excel',
    description: '从 PDF 中提取表格数据到 Excel',
    seoDescription: '在线 PDF 转 Excel 工具，快速提取 PDF 中的表格数据并转换为 Excel 文件（.xlsx格式）。智能识别表格结构，保持数据完整性。',
    icon: <FileExcelOutlined style={{ fontSize: 48, color: '#52c41a' }} />,
    accept: '.pdf',
    buttonText: '开始转换',
    keywords: 'PDF转Excel, PDF转Excel在线, PDF表格提取'
  },
  {
    id: 'pdf2ppt',
    title: 'PDF 转 PPT',
    description: '将 PDF 转换为 PowerPoint 演示文稿',
    seoDescription: '免费 PDF 转 PPT 工具，将 PDF 文件转换为 PowerPoint 演示文稿（.pptx格式）。适合将文档快速转换为可编辑的幻灯片。',
    icon: <FilePptOutlined style={{ fontSize: 48, color: '#fa8c16' }} />,
    accept: '.pdf',
    buttonText: '开始转换',
    keywords: 'PDF转PPT, PDF转PowerPoint, PDF转幻灯片'
  },
  {
    id: 'merge',
    title: 'PDF 合并',
    description: '将多个 PDF 文件合并为一个',
    seoDescription: '在线 PDF 合并工具，快速将多个 PDF 文件合并为一个完整的 PDF 文档。支持批量上传，保持原有质量。',
    icon: <MergeCellsOutlined style={{ fontSize: 48, color: '#722ed1' }} />,
    accept: '.pdf',
    buttonText: '开始合并',
    multiple: true,
    keywords: 'PDF合并, 合并PDF, PDF文件合并'
  },
  {
    id: 'split',
    title: 'PDF 拆分',
    description: '将一个 PDF 文件拆分为多个',
    seoDescription: '免费 PDF 拆分工具，将大型 PDF 文件拆分为多个独立的 PDF 文档。支持按页数拆分，操作简单快捷。',
    icon: <ScissorOutlined style={{ fontSize: 48, color: '#eb2f96' }} />,
    accept: '.pdf',
    buttonText: '开始拆分',
    keywords: 'PDF拆分, 拆分PDF, PDF分割'
  }
]

function App() {
  const [currentFeature, setCurrentFeature] = useState(null)
  const [file, setFile] = useState(null)
  const [files, setFiles] = useState([])
  const [converting, setConverting] = useState(false)
  const [progress, setProgress] = useState(0)
  const [result, setResult] = useState(null)

  // 生成客户端 ID
  const getClientId = () => {
    let clientId = localStorage.getItem('client_id')
    if (!clientId) {
      clientId = 'client_' + Math.random().toString(36).substr(2, 9)
      localStorage.setItem('client_id', clientId)
    }
    return clientId
  }

  // 处理文件上传
  const handleUpload = async (taskType) => {
    if (!file) {
      message.error('请先选择 PDF 文件')
      return
    }

    setConverting(true)
    setProgress(0)
    setResult(null)

    try {
      // 1. 上传文件到服务器
      const formData = new FormData()
      formData.append('file', file)

      const uploadRes = await axios.post(`${API_BASE_URL}/upload`, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
        onUploadProgress: (progressEvent) => {
          const percentCompleted = Math.round((progressEvent.loaded * 50) / progressEvent.total)
          setProgress(percentCompleted)
        }
      })

      const fileKey = uploadRes.data.file_key
      setProgress(50)

      // 2. 创建转换任务
      const taskRes = await axios.post(`${API_BASE_URL}/tasks`, {
        file_key: fileKey,
        task_type: taskType,
        file_name: file.name,
        file_size: file.size,
        client_id: getClientId()
      })

      const taskId = taskRes.data.task_id

      // 3. 轮询任务状态
      const pollTask = async () => {
        const statusRes = await axios.get(`${API_BASE_URL}/tasks/${taskId}`)
        const status = statusRes.data.status

        if (status === 'completed') {
          setProgress(100)
          setResult(statusRes.data)
          message.success('转换完成！')
          setConverting(false)
        } else if (status === 'failed') {
          message.error('转换失败: ' + statusRes.data.error_msg)
          setConverting(false)
        } else if (status === 'processing') {
          setProgress(prev => Math.min(prev + 10, 90))
          setTimeout(pollTask, 2000)
        } else {
          setTimeout(pollTask, 2000)
        }
      }

      setTimeout(pollTask, 2000)

    } catch (error) {
      console.error('Upload error:', error)

      if (error.response?.status === 402) {
        message.warning('文件过大，需要付费解锁')
      } else {
        message.error('上传失败: ' + (error.response?.data?.detail || error.message))
      }

      setConverting(false)
    }
  }

  const uploadProps = {
    name: 'file',
    multiple: currentFeature?.multiple || false,
    accept: currentFeature?.accept || '.pdf',
    beforeUpload: (file) => {
      if (file.type !== 'application/pdf') {
        message.error('只支持 PDF 文件')
        return Upload.LIST_IGNORE
      }

      if (file.size > 500 * 1024 * 1024) {
        message.error('文件过大，最大支持 500MB')
        return Upload.LIST_IGNORE
      }

      if (currentFeature?.multiple) {
        setFiles(prev => [...prev, file])
        message.success(`已添加: ${file.name}`)
      } else {
        setFile(file)
        message.success(`已选择: ${file.name}`)
      }
      return false
    }
  }

  // 返回首页
  const goBack = () => {
    setCurrentFeature(null)
    setFile(null)
    setFiles([])
    setConverting(false)
    setProgress(0)
    setResult(null)
  }

  // 选择功能
  const selectFeature = (feature) => {
    setCurrentFeature(feature)
    setFile(null)
    setFiles([])
    setResult(null)
  }

  // 渲染功能选择页面
  const renderFeatureSelection = () => (
    <div style={{ marginTop: 32 }}>
      {/* SEO 友好的介绍文本 */}
      <div style={{ textAlign: 'center', marginBottom: 40, maxWidth: 800, margin: '0 auto 40px' }}>
        <Title level={2} style={{ marginBottom: 16 }}>
          专业的在线 PDF 转换工具
        </Title>
        <Text style={{ fontSize: 16, lineHeight: 1.8, display: 'block', color: 'rgba(255,255,255,0.9)' }}>
          PDFShift 提供免费、快速、安全的在线 PDF 转换服务。支持 PDF 转 Word、PDF 转 Excel、PDF 转 PPT、
          PDF 合并和 PDF 拆分等多种功能。无需安装任何软件，在浏览器中即可完成 PDF 文件的转换和处理。
          我们采用先进的 PDF 解析技术，确保转换质量和文档格式的完整性。
        </Text>
      </div>

      {/* 功能卡片 */}
      <Title level={3} style={{ textAlign: 'center', marginBottom: 24 }}>
        选择您需要的功能
      </Title>
      <Row gutter={[24, 24]}>
        {FEATURES.map(feature => (
          <Col xs={24} sm={12} md={8} key={feature.id}>
            <Card
              hoverable
              onClick={() => selectFeature(feature)}
              style={{ textAlign: 'center', height: '100%' }}
              aria-label={feature.title}
            >
              <article style={{ padding: '20px 0' }}>
                {feature.icon}
                <Title level={4} style={{ marginTop: 16, marginBottom: 8 }}>
                  {feature.title}
                </Title>
                <Text type="secondary">{feature.description}</Text>
              </article>
            </Card>
          </Col>
        ))}
      </Row>

      {/* SEO 隐藏内容 - 为搜索引擎提供更多关键词 */}
      <div style={{ marginTop: 60, maxWidth: 900, margin: '60px auto 0', textAlign: 'left' }}>
        <Title level={3} style={{ color: 'white', marginBottom: 20 }}>
          为什么选择 PDFShift？
        </Title>
        <Row gutter={[16, 16]}>
          <Col xs={24} md={12}>
            <Card size="small">
              <h4>🚀 快速高效</h4>
              <p>采用云端处理技术，转换速度快，支持大文件处理，最大支持 500MB。</p>
            </Card>
          </Col>
          <Col xs={24} md={12}>
            <Card size="small">
              <h4>🔒 安全可靠</h4>
              <p>文件加密传输，转换后自动删除，保护您的隐私和数据安全。</p>
            </Card>
          </Col>
          <Col xs={24} md={12}>
            <Card size="small">
              <h4>💯 完全免费</h4>
              <p>50MB 以下文件完全免费，无需注册登录，随时随地使用。</p>
            </Card>
          </Col>
          <Col xs={24} md={12}>
            <Card size="small">
              <h4>🎯 格式保留</h4>
              <p>智能识别文档结构，保持原有格式、图片和布局不变。</p>
            </Card>
          </Col>
        </Row>
      </div>
    </div>
  )

  // 渲染转换页面
  const renderConversionPage = () => (
    <article style={{ marginTop: 32 }}>
      <Button
        icon={<ArrowLeftOutlined />}
        onClick={goBack}
        style={{ marginBottom: 16 }}
      >
        返回首页
      </Button>

      <Card>
        <header>
          <Title level={2}>{currentFeature.title}</Title>
          <Text type="secondary" style={{ fontSize: 16, display: 'block', marginBottom: 8 }}>
            {currentFeature.seoDescription}
          </Text>
        </header>

        <div style={{ marginTop: 24 }}>
          <Dragger {...uploadProps} disabled={converting}>
            <p className="ant-upload-drag-icon">
              <InboxOutlined />
            </p>
            <p className="ant-upload-text">
              {currentFeature.multiple ? '点击或拖拽 PDF 文件到此区域（可选择多个）' : '点击或拖拽 PDF 文件到此区域'}
            </p>
            <p className="ant-upload-hint">
              支持{currentFeature.multiple ? '多个' : '单个'}文件上传，每个文件最大 500MB
            </p>
          </Dragger>

          {currentFeature.multiple && files.length > 0 && (
            <div style={{ marginTop: 16 }}>
              <Text strong>已选择 {files.length} 个文件：</Text>
              <ul>
                {files.map((f, idx) => (
                  <li key={idx}>{f.name}</li>
                ))}
              </ul>
            </div>
          )}

          {((file && !currentFeature.multiple) || (files.length > 0 && currentFeature.multiple)) && !converting && !result && (
            <div style={{ marginTop: 24, textAlign: 'center' }}>
              <Button
                type="primary"
                size="large"
                icon={currentFeature.icon}
                onClick={() => handleUpload(currentFeature.id)}
              >
                {currentFeature.buttonText}
              </Button>
            </div>
          )}

          {converting && (
            <div style={{ marginTop: 24 }}>
              <Progress percent={progress} status="active" />
              <Text type="secondary">正在处理中，请稍候...</Text>
            </div>
          )}

          {result && (
            <Card style={{ marginTop: 24 }} type="inner">
              <Title level={4}>处理完成！</Title>
              <Text>文件名: {result.file_name}</Text>
              <br />
              <Button
                type="primary"
                style={{ marginTop: 16 }}
                href={result.download_url}
                download
              >
                下载文件
              </Button>
              <Text type="secondary" style={{ marginLeft: 16 }}>
                文件将在 1 小时后自动删除
              </Text>
              <br />
              <Button
                style={{ marginTop: 16 }}
                onClick={goBack}
              >
                继续处理其他文件
              </Button>
            </Card>
          )}
        </div>
      </Card>
    </article>
  )

  return (
    <div className="app">
      <div className="container">
        <header style={{ marginBottom: 8 }}>
          <Title level={1} style={{ marginBottom: 8 }}>
            PDFShift - 免费在线 PDF 转换工具
          </Title>
          <Text type="secondary" style={{ fontSize: 16 }}>
            专业的在线 PDF 转换平台 | 支持 PDF 转 Word、Excel、PPT、合并、拆分 | 免费、快速、安全
          </Text>
        </header>

        <main>
          {!currentFeature ? renderFeatureSelection() : renderConversionPage()}
        </main>

        <footer className="footer">
          <Text type="secondary">
            © 2026 PDFShift - 在线 PDF 转换工具 | <a href="/privacy">隐私政策</a> | <a href="/terms">用户协议</a>
          </Text>
          <br />
          <Text type="secondary" style={{ fontSize: 12 }}>
            关键词：PDF转换器、PDF转Word、PDF转Excel、PDF转PPT、PDF合并、PDF拆分、在线PDF工具
          </Text>
        </footer>
      </div>
    </div>
  )
}

export default App
