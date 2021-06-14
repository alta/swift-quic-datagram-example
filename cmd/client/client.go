package main

import (
	"crypto/tls"
	"flag"
	"log"

	"github.com/alta/swift-quic-datagram-example/internal/insecure"
	quic "github.com/lucas-clemente/quic-go"
)

func main() {
	addr := flag.String("a", "localhost:4242", "address in host:port format")
	flag.Parse()
	message := flag.Arg(0)
	if message == "" {
		message = "hello"
	}

	err := clientMain(*addr, message)
	if err != nil {
		log.Fatal(err)
	}
}

func clientMain(addr, message string) error {
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

	sess, err := quic.DialAddr(addr, tlsConfig, quicConfig)
	if err != nil {
		return err
	}

	log.Printf("SendMessage: %v\n", message)

	err = sess.SendMessage([]byte(message))
	if err != nil {
		return err
	}

	buf, err := sess.ReceiveMessage()
	if err != nil {
		return err
	}
	log.Printf("ReceiveMessage: %v\n", string(buf))

	return nil
}
