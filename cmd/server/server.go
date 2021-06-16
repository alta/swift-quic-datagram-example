package main

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"

	"github.com/alta/swift-quic-datagram-example/internal/insecure"
	quic "github.com/lucas-clemente/quic-go"
	"github.com/lucas-clemente/quic-go/logging"
	"github.com/lucas-clemente/quic-go/qlog"
)

func main() {
	addr := flag.String("a", "localhost:4242", "address in host:port format")
	flag.Parse()

	err := serverMain(*addr)
	if err != nil {
		log.Fatal(err)
	}
}

func serverMain(addr string) error {
	cert, pool, err := insecure.LocalCertPool(addr)
	if err != nil {
		return err
	}

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
		RootCAs:      pool,
		NextProtos:   []string{"echo"},
	}

	quicConfig := &quic.Config{
		EnableDatagrams: true,
	}

	qlogDir := os.Getenv("QUIC_LOG_DIRECTORY")
	if qlogDir != "" {
		quicConfig.Tracer = qlog.NewTracer(func(_ logging.Perspective, connID []byte) io.WriteCloser {
			fn := filepath.Join(qlogDir, fmt.Sprintf("server-%x.qlog", connID))
			f, err := os.Create(fn)
			if err != nil {
				log.Fatal(err)
			}
			log.Printf("Created qlog file: %s", fn)
			return f
		})
	}

	listener, err := quic.ListenAddr(addr, tlsConfig, quicConfig)
	if err != nil {
		return err
	}

	log.Printf("Server listening at: %s", addr)

	for {
		sess, err := listener.Accept(context.Background())
		if err != nil {
			return err
		}
		go func(sess quic.Session) {
			log.Printf("QUIC session started: %s %t",
				sess.RemoteAddr().String(), sess.ConnectionState().SupportsDatagrams)
			for {
				buf, err := sess.ReceiveMessage()
				if err != nil {
					log.Printf("Error: ReceiveMessage: %s\n", string(buf))
					break
				}
				log.Printf("ReceiveMessage: %s\n", string(buf))
				err = sess.SendMessage(buf)
				if err != nil {
					log.Printf("Error: SendMessage: %v", err)
					break
				}
				log.Printf("SendMessage: %s\n", string(buf))
			}
		}(sess)
	}
}
